class SubUser < ApplicationRecord
  # bcrypt-backed PIN. validations: false because the digest is set out of band
  # (console / admin), not on every save.
  has_secure_password :pin, validations: false

  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT             = 5.minutes

  validates :name, presence: true, uniqueness: true
  validates :pin, format: { with: /\A\d{4}\z/, message: "must be 4 digits" }, allow_nil: true

  scope :enabled,  -> { where(enabled: true) }
  scope :in_order, -> { order(:name) }

  # Duck-types User for anything that stamps the process record.
  def display_name
    name
  end

  def active?
    enabled
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
end
