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

  def sees_ecards?
    case email_address
    when 'judy@hardanodisingstl.com'
      false # Judy won't use the app
    when 'chris.bayliss@hardanodisingstl.com',
         'julia@hardanodisingstl.com',
         'sophie@hardanodisingstl.com'
      false # Office staff - no e-cards
    else
      true
    end
  end

  def can_reissue_documents?
    email_address.in?([
      'quality@hardanodisingstl.com',    # Jim Ledger
      'chris@hardanodisingstl.com'       # Chris Connon
    ])
  end

  # Returns filtering criteria for e-cards based on user role
  def ecard_filter_criteria
    return {} unless sees_ecards?

    case email_address
    when 'adrian@hardanodisingstl.com'
      adrian_bishop_filter
    when 'alan@hardanodisingstl.com'
      alan_vaughan_filter
    when 'ben@hardanodisingstl.com'
      ben_mcgowan_filter
    when 'brian@hardanodisingstl.com'
      brian_benton_filter
    when 'chris@hardanodisingstl.com'
      chris_connon_filter
    when 'daniel@hardanodisingstl.com'
      daniel_bayliss_filter
    when 'dave@hardanodisingstl.com'
      dave_bennett_filter
    when 'elena@hardanodisingstl.com'
      elena_oprea_filter
    when 'gary@hardanodisingstl.com'
      gary_rickets_filter
    when 'quality@hardanodisingstl.com'
      jim_ledger_filter
    when 'nigel@hardanodisingstl.com'
      nigel_harrington_filter
    when 'phil@hardanodisingstl.com'
      phil_bayliss_filter
    when 'ross@hardanodisingstl.com'
      ross_wilson_filter
    when 'tariq@hardanodisingstl.com'
      tariq_anwar_filter
    else
      {} # No filtering for unrecognized users
    end
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
  end

  # ============================================================================
  # INDIVIDUAL USER FILTER METHODS
  # ============================================================================

  # Adrian Bishop - VAT 9 & 12 work
  def adrian_bishop_filter
    {
      vat_numbers: [9, 12],
      description: "VAT 9 & 12 work"
    }
  end

  # Alan Vaughan - Lab work (sees all since testing is rare)
  def alan_vaughan_filter
    {
      description: "Lab work - sees all work since testing is rare"
    }
  end

  # Ben McGowan - VAT 9 & 12 work
  def ben_mcgowan_filter
    {
      vat_numbers: [9, 12],
      description: "VAT 9 & 12 work"
    }
  end

  # Brian Benton - General work, VATs 1-3, no ENP
  def brian_benton_filter
    {
      vat_numbers: [1, 2, 3],
      exclude_process_types: ['electroless_nickel_plating'],
      description: "General work, VATs 1-3, no ENP"
    }
  end

  # Chris Connon - Quality/NCRs (sees all e-cards)
  def chris_connon_filter
    {
      description: "Quality/NCRs - sees all e-cards"
    }
  end

  # Daniel Bayliss - Developer (sees everything - both Xero and all e-cards)
  def daniel_bayliss_filter
    {
      description: "Developer - sees all work and systems"
    }
  end

  # Dave Bennett - Maintenance (basic access)
  def dave_bennett_filter
    {
      basic_access_only: true,
      description: "Maintenance - basic access"
    }
  end

  # Elena Oprea - Quality inspector (sees all e-cards)
  def elena_oprea_filter
    {
      description: "Quality inspector - sees all e-cards"
    }
  end

  # Gary Rickets - VAT 5 & 6 (hard/standard anodising), no ENP
  def gary_rickets_filter
    {
      vat_numbers: [5, 6],
      process_types: ['hard_anodising', 'standard_anodising'],
      exclude_process_types: ['electroless_nickel_plating'],
      description: "VAT 5 & 6 hard/standard anodising, no ENP"
    }
  end

  # Jim Ledger - Quality/NCRs (sees all e-cards)
  def jim_ledger_filter
    {
      description: "Quality/NCRs - sees all e-cards"
    }
  end

  # Nigel Harrington - Contract reviewer (sees all e-cards)
  def nigel_harrington_filter
    {
      description: "Contract reviewer - sees all e-cards"
    }
  end

  # Phil Bayliss - Managing Director (sees all e-cards)
  def phil_bayliss_filter
    {
      description: "Managing Director - sees all e-cards"
    }
  end

  # Ross Wilson - Chromic acid anodising and chemical conversion priority
  def ross_wilson_filter
    {
      process_types: ['chromic_anodising', 'chemical_conversion'],
      priority_process_types: ['chromic_anodising', 'chemical_conversion'],
      description: "Chromic acid anodising and chemical conversion priority"
    }
  end

  # Tariq Anwar - Senior Management (sees all e-cards)
  def tariq_anwar_filter
    {
      description: "Senior Management - sees all e-cards"
    }
  end
end
