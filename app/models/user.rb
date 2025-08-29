class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # Domain restriction for Hard Anodising Surface Treatments
  validates :email_address,
            presence: true,
            uniqueness: true,
            format: {
              with: /@hardanodisingstl\.com\z/,
              message: "must be a Hard Anodising Surface Treatments email address"
            }

  validates :username, presence: true, uniqueness: true
  validates :full_name, presence: true

  # Default enabled to true for new users
  after_initialize :set_defaults, if: :new_record?

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }

  def display_name
    full_name.present? ? full_name : username
  end

  def active?
    enabled
  end

  # Magic link token generation
  def generate_magic_link_token
    self.magic_link_token = SecureRandom.urlsafe_base64(32)
    self.magic_link_expires_at = 15.minutes.from_now
    save!
    magic_link_token
  end

  # Check if magic link is valid
  def magic_link_valid?(token)
    return false unless magic_link_token.present? && magic_link_expires_at.present?
    return false if magic_link_expires_at < Time.current

    ActiveSupport::SecurityUtils.secure_compare(magic_link_token, token)
  end

  # Clear magic link after use
  def clear_magic_link!
    self.magic_link_token = nil
    self.magic_link_expires_at = nil
    save!
  end

  # Class method to find by valid magic link
  def self.find_by_magic_link(token)
    return nil if token.blank?

    user = find_by(magic_link_token: token)
    return nil unless user&.magic_link_valid?(token)

    user
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end
end
