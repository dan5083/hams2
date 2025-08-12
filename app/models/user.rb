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

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end
end
