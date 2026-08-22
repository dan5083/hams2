class User < ApplicationRecord
  KIOSK_EMAIL = "kiosk@hardanodisingstl.com".freeze

  has_secure_password
  has_many :sessions, dependent: :destroy

  # This login's operator identity. nullify, never destroy - historical
  # sign-offs name the operator row and it must outlive the login.
  has_one :sub_user, dependent: :nullify

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

  # Users are created in the console only. Every real person gets an operator
  # identity at the same moment, so they can PIN on at any terminal.
  after_create :ensure_sub_user!

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }

  def display_name
    full_name.present? ? full_name : username
  end

  def active?
    enabled
  end

  def kiosk?
    email_address == KIOSK_EMAIL
  end

  # Whether a mark on a process record may be attributed to this account when
  # no operator is unlocked. The kiosk is a shared login with no name of its
  # own, so never.
  def can_sign_off?
    !kiosk?
  end

  # Creates (or claims, by exact name match) this user's operator row. Safe to
  # re-run; used by the console backfill as well as after_create. Claiming an
  # existing floor operator avoids two rows for one person, but check the dry
  # run - two different people with the same full name would bind wrongly.
  def ensure_sub_user!
    return if kiosk?
    return if sub_user.present?

    existing = SubUser.floor.find_by(name: full_name)
    if existing
      existing.update!(user: self)
    else
      SubUser.create!(name: full_name, user: self, enabled: enabled != false)
    end
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

  # ============================================================================
  # ROLE-BASED ACCESS CONTROL
  # ============================================================================

  # Main permission methods
  def sees_xero_integration?
    case email_address
    when 'chris.bayliss@hardanodisingstl.com',
         'daniel@hardanodisingstl.com',
         'julia@hardanodisingstl.com',
         'phil@hardanodisingstl.com',
         'sophie@hardanodisingstl.com',
         'tariq@hardanodisingstl.com'
      true
    else
      false
    end
  end

  def can_use_ai_assistant?
    email_address.in?([
      'daniel@hardanodisingstl.com',
      'tariq@hardanodisingstl.com',
      'phil@hardanodisingstl.com',
      'brian@hardanodisingstl.com',
      'chris@hardanodisingstl.com',
      'sophie@hardanodisingstl.com',
      'julia@hardanodisingstl.com',
      'nigel@hardanodisingstl.com'
    ])
  end

  def can_reissue_documents?
    email_address.in?([
      'quality@hardanodisingstl.com',    # Jim Ledger
      'chris@hardanodisingstl.com'       # Chris Connon
    ])
  end

  def sees_ncrs?
    email_address != 'judy@hardanodisingstl.com'
  end

  def can_manage_ncrs?
    email_address.in?([
      'quality@hardanodisingstl.com',  # Jim Ledger
      'chris@hardanodisingstl.com',    # Chris Connon
      'phil@hardanodisingstl.com',     # Phil Bayliss
      'tariq@hardanodisingstl.com',    # Tariq Anwar
      'daniel@hardanodisingstl.com'    # Daniel Bayliss
    ])
  end

  def can_edit_quality_documents?
    email_address.in?([
      'quality@hardanodisingstl.com',    # Jim Ledger
      'chris@hardanodisingstl.com',      # Chris Connon
      'daniel@hardanodisingstl.com',     # Daniel Bayliss
      'phil@hardanodisingstl.com'        # Phil Bayliss
    ])
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end
end
