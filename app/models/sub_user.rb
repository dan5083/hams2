class SubUser < ApplicationRecord
  # bcrypt-backed PIN. validations: false because the digest is set out of band
  # (console / admin), not on every save.
  #
  # PIN-only sign-on: the PIN *is* the identity, so every PIN must be unique
  # across all sub-users (enforced by the unique index on pin_lookup) and must
  # always be set via pin= / reset_pin! - never by writing pin_digest directly,
  # or the lookup column goes stale and the operator can't sign on.
  has_secure_password :pin, validations: false

  # A staff login's operator identity. Nil for floor operators, who exist only
  # here. Deleting a User must never delete the operator row that historical
  # sign-offs name, hence dependent: :nullify on the other side.
  belongs_to :user, optional: true

  # PINs nobody gets to have: trivially guessable on a keypad in open view.
  BANNED_PINS = %w[0000 1111 2222 3333 4444 5555 6666 7777 8888 9999
                   0123 1234 2345 3456 4567 5678 6789 4321 9876].freeze

  validates :name, presence: true, uniqueness: true
  validates :pin, format: { with: /\A\d{4}\z/, message: "must be 4 digits" }, allow_nil: true
  validates :pin, exclusion: { in: BANNED_PINS, message: "is too easy to guess" }, allow_nil: true
  # Friendly message for what the unique index enforces anyway. Uniqueness is
  # global, not just signable: re-enabling a retired operator must not be able
  # to create a collision after the fact.
  validates :pin_lookup, uniqueness: { message: "is already in use by another operator" }, allow_nil: true
  validate  :kiosk_cannot_be_an_operator

  scope :enabled,  -> { where(enabled: true) }
  scope :in_order, -> { order(:name) }
  scope :staff,    -> { where.not(user_id: nil) }
  scope :floor,    -> { where(user_id: nil) }

  # Operators who may appear on the sign-on list. A staff operator whose login
  # has been disabled disappears here as a consequence of the join - nothing to
  # remember to mirror. users.enabled is nullable, and NULL means enabled.
  scope :signable, -> {
    enabled.left_joins(:user)
           .where("sub_users.user_id IS NULL OR users.enabled IS NOT FALSE")
  }

  # Keep the deterministic lookup column in step with the digest. HMAC keyed on
  # the server secret: constant-time to find, and useless to anyone holding a
  # copy of the table without the key.
  def pin=(plain)
    super
    self.pin_lookup = plain.present? ? self.class.pin_lookup_for(plain) : nil
  end

  def self.pin_lookup_for(plain)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "sub_user_pin:#{plain}")
  end

  # The whole sign-on: who does this PIN belong to? Only signable operators
  # can be found - a disabled staff login still kills the PIN with it.
  #
  # Fast path is the indexed HMAC lookup. But existing operators kept their old
  # bcrypt PINs through the cutover and start with a NULL pin_lookup, so we
  # fall back to bcrypt-scanning just the not-yet-migrated ones and backfill
  # the lookup on the way through. That set only shrinks: once someone signs on
  # they're on the fast path forever, and within a shift or two the scan is
  # empty. No PIN reissue, no scan cost in steady state.
  def self.find_by_pin(plain)
    plain = plain.to_s
    return nil unless plain.match?(/\A\d{4}\z/)

    hit = signable.find_by(pin_lookup: pin_lookup_for(plain))
    return hit if hit&.authenticate_pin(plain)

    migrate_pin_lookup(plain)
  end

  # Fallback scan over operators still on the old digest with no lookup yet.
  def self.migrate_pin_lookup(plain)
    signable.where(pin_lookup: nil).where.not(pin_digest: nil).find_each do |op|
      next unless op.authenticate_pin(plain)

      begin
        op.update_column(:pin_lookup, pin_lookup_for(plain))
      rescue ActiveRecord::RecordNotUnique
        # Someone with the SAME PIN already migrated. Under the old dropdown a
        # shared PIN was harmless - you picked the name. It can't be now, so
        # this operator needs a fresh PIN from Tariq. Refuse rather than sign
        # the wrong person on.
        Rails.logger.warn "=== SUB-USER: #{op.name} shares a PIN with an already-migrated operator - needs reissue ==="
        return nil
      end
      return op
    end
    nil
  end

  # Duck-types User for anything that stamps the process record.
  def display_name
    name
  end

  def active?
    enabled
  end

  def can_sign_on?
    enabled? && (user.nil? || user.enabled != false)
  end

  # Same test - if you're entitled to unlock, you're entitled to sign.
  def can_sign_off?
    can_sign_on?
  end

  # No automatic locking any more - a wrong PIN belongs to nobody, so failures
  # can't be counted against an operator. This survives as a manual lock:
  # set pin_locked_until from the console to bench someone's PIN.
  def locked?
    pin_locked_until.present? && pin_locked_until > Time.current
  end

  def lock_expires_in
    return nil unless locked?
    ((pin_locked_until - Time.current) / 60.0).ceil
  end

  # Generates and sets a random PIN, returning the plaintext once so it can be
  # handed to the operator. Nothing stores the plaintext. Skips banned PINs and
  # ones already in use - uniqueness is the whole scheme now.
  def reset_pin!(tries: 50)
    tries.times do
      plain = format("%04d", SecureRandom.random_number(10_000))
      next if BANNED_PINS.include?(plain)
      next if self.class.where.not(id: id).exists?(pin_lookup: self.class.pin_lookup_for(plain))

      update!(pin: plain, failed_pin_count: 0, pin_locked_until: nil)
      return plain
    end
    raise "Couldn't find a free PIN after #{tries} tries"
  end

  private

    # The shared shop-floor login has no name of its own. Nothing on a process
    # record may ever be attributed to it.
    def kiosk_cannot_be_an_operator
      errors.add(:user, "is the shared kiosk login and cannot be an operator") if user&.kiosk?
    end
end
