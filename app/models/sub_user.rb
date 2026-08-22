class SubUser < ApplicationRecord
  # bcrypt-backed PIN. validations: false because the digest is set out of band
  # (console / admin), not on every save.
  has_secure_password :pin, validations: false

  # A staff login's operator identity. Nil for floor operators, who exist only
  # here. Deleting a User must never delete the operator row that historical
  # sign-offs name, hence dependent: :nullify on the other side.
  belongs_to :user, optional: true

  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT             = 5.minutes

  validates :name, presence: true, uniqueness: true
  validates :pin, format: { with: /\A\d{4}\z/, message: "must be 4 digits" }, allow_nil: true
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

  def locked?
    pin_locked_until.present? && pin_locked_until > Time.current
  end

  def lock_expires_in
    return nil unless locked?
    ((pin_locked_until - Time.current) / 60.0).ceil
  end

  # Returns :ok, :invalid or :locked. Counts failures and locks the operator
  # out for a few minutes so a 4-digit PIN can't be walked through on a
  # touchscreen sitting in the middle of the shop.
  def verify_pin(candidate)
    return :locked  if locked?
    return :invalid unless can_sign_on?
    return :invalid if pin_digest.blank?

    if authenticate_pin(candidate.to_s)
      update_columns(failed_pin_count: 0, pin_locked_until: nil)
      :ok
    else
      count = failed_pin_count.to_i + 1
      if count >= MAX_FAILED_ATTEMPTS
        update_columns(failed_pin_count: count, pin_locked_until: LOCKOUT.from_now)
        :locked
      else
        update_columns(failed_pin_count: count, pin_locked_until: nil)
        :invalid
      end
    end
  end

  # Generates and sets a random PIN, returning the plaintext once so it can be
  # handed to the operator. Nothing stores the plaintext.
  def reset_pin!
    plain = format("%04d", SecureRandom.random_number(10_000))
    update!(pin: plain, failed_pin_count: 0, pin_locked_until: nil)
    plain
  end

  private

    # The shared shop-floor login has no name of its own. Nothing on a process
    # record may ever be attributed to it.
    def kiosk_cannot_be_an_operator
      errors.add(:user, "is the shared kiosk login and cannot be an operator") if user&.kiosk?
    end
end
