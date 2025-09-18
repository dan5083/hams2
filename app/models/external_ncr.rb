# app/models/external_ncr.rb
class ExternalNcr < ApplicationRecord
  belongs_to :release_note
  belongs_to :created_by, class_name: 'User'
  belongs_to :assigned_to, class_name: 'User', optional: true

  # Delegate common fields to release_note -> works_order for easy access
  has_one :works_order, through: :release_note
  has_one :customer_order, through: :works_order
  has_one :customer, through: :customer_order
  has_one :part, through: :works_order

  # JSONB accessors for NCR-specific data
  store_accessor :ncr_data,
    # Identification numbers
    :advice_number,
    :release_number,
    :concession_number,
    :customer_po_number,
    :customer_ncr_number,

    # Quantities
    :batch_quantity,
    :reject_quantity,

    # NCR Content
    :description_of_non_conformance,
    :investigation_root_cause_analysis,
    :root_cause_identified,
    :containment_corrective_action,
    :preventive_action,
    :completed_by_user_id

  validates :hal_ncr_number, presence: true, uniqueness: true, numericality: { greater_than: 0 }
  validates :release_note_id, presence: true
  validates :date, presence: true
  validates :created_by_id, presence: true
  validates :status, inclusion: { in: %w[draft in_progress completed] }

  # Validate quantities if provided
  validates :batch_quantity, numericality: { greater_than: 0 }, allow_blank: true
  validates :reject_quantity, numericality: { greater_than: 0 }, allow_blank: true

  # Scopes
  scope :active, -> { where.not(status: 'completed') }
  scope :by_status, ->(status) { where(status: status) }
  scope :for_customer, ->(customer) { joins(:customer).where(customer: customer) }
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :set_ncr_number, if: :new_record?
  before_validation :set_defaults, if: :new_record?
  after_create :log_creation
  after_update :log_status_change, if: :saved_change_to_status?

  def display_name
    "NCR#{hal_ncr_number}"
  end

  def display_title
    "NCR#{hal_ncr_number} - #{customer_name} - #{part_display_name} - RN#{release_note.number}"
  end

  # Delegated attributes from release_note -> works_order
  def customer_name
    customer&.name
  end

  def part_display_name
    works_order&.part&.display_name
  end

  def part_number
    works_order&.part_number
  end

  def part_issue
    works_order&.part_issue
  end

  def part_description
    works_order&.part_description
  end

  def works_order_number
    works_order&.display_name
  end

  def release_note_number
    "RN#{release_note.number}"
  end

  # Status management
  def next_status
    case status
    when 'draft' then 'in_progress'
    when 'in_progress' then 'completed'
    else nil
    end
  end

  def can_advance_status?
    case status
    when 'draft'
      description_of_non_conformance.present?
    when 'in_progress'
      containment_corrective_action.present? && preventive_action.present?
    else
      false
    end
  end

  def advance_status!
    return false unless can_advance_status?

    new_status = next_status
    return false unless new_status

    if new_status == 'completed'
      self.completed_by_user_id = Current.user&.id
    end

    update!(status: new_status)
  end

  # Status badge CSS class
  def status_badge_class
    case status
    when 'draft'
      'bg-gray-100 text-gray-800'
    when 'in_progress'
      'bg-yellow-100 text-yellow-800'
    when 'completed'
      'bg-green-100 text-green-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end

  # Search functionality
  def self.search(term)
    return all if term.blank?

    term = term.strip

    # Handle NCR prefix search (e.g., "NCR123" -> search for hal_ncr_number = 123)
    if term.match(/^NCR(\d+)$/i)
      ncr_number = term.match(/^NCR(\d+)$/i)[1].to_i
      return where(hal_ncr_number: ncr_number)
    end

    # General search
    joins(release_note: { works_order: :customer_order })
      .joins(customer: [])
      .where(
        "CAST(hal_ncr_number AS TEXT) ILIKE ? OR " \
        "organizations.name ILIKE ? OR " \
        "works_orders.part_number ILIKE ?",
        "%#{term}%", "%#{term}%", "%#{term}%"
      )
      .distinct
  end

  private

  def set_ncr_number
    sequence = Sequence.find_or_create_by(key: 'external_ncr_number')
    self.hal_ncr_number = sequence.value
    sequence.increment!(:value)
  end

  def set_defaults
    self.date ||= Date.current
    self.status ||= 'draft'
    self.ncr_data ||= {}
  end

  def log_creation
    Rails.logger.info "Created External NCR #{hal_ncr_number} for Release Note #{release_note.number}"
  end

  def log_status_change
    Rails.logger.info "External NCR #{hal_ncr_number} status changed from #{status_before_last_save} to #{status}"
  end
end
