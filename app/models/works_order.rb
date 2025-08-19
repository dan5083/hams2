# app/models/works_order.rb - Enhanced with auto-completion
class WorksOrder < ApplicationRecord
  belongs_to :customer_order
  belongs_to :part, optional: true
  belongs_to :release_level
  belongs_to :transport_method
  belongs_to :ppi, class_name: 'PartProcessingInstruction', optional: true

  has_many :release_notes, dependent: :restrict_with_error

  validates :part_number, presence: true
  validates :part_issue, presence: true
  validates :part_description, presence: true
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :quantity_released, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :lot_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :price_type, inclusion: { in: %w[each lot] }

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }
  scope :open, -> { where(is_open: true) }
  scope :closed, -> { where(is_open: false) }
  scope :for_customer, ->(customer) { joins(:customer_order).where(customer_orders: { customer: customer }) }

  before_validation :calculate_pricing, if: :pricing_fields_changed?
  before_validation :set_part_details_from_ppi, if: :ppi_id_changed?
  before_validation :normalize_part_details
  before_validation :assign_next_number, if: :new_record?
  after_initialize :set_defaults, if: :new_record?

  # AUTO-COMPLETION: Automatically close when fully released
  after_update :auto_complete_if_fully_released

  def display_name
    "WO#{number} - #{part_number}"
  end

  # Delegate customer info to customer_order
  def customer
    customer_order.customer
  end

  def invoice_customer_name
    customer_order.invoice_customer_name
  end

  def invoice_address
    customer_order.invoice_address
  end

  def delivery_customer_name
    customer_order.delivery_customer_name
  end

  def delivery_address
    customer_order.delivery_address
  end

  def specification
    ppi&.specification || "Process as per customer requirements for #{part_number}-#{part_issue}"
  end

  def special_instructions
    ppi&.special_instructions
  end

  def quantity_remaining
    quantity - quantity_released
  end

  # NEW: Check if manufacturing is complete (all parts released)
  def manufacturing_complete?
    quantity_released >= quantity
  end

  def void!
    transaction do
      if release_notes.active.exists?
        raise StandardError, "Cannot void works order with active release notes"
      end
      update!(voided: true)
    end
  end

  def calculate_quantity_released!
    total = release_notes.active.sum(:quantity_accepted) + release_notes.active.sum(:quantity_rejected)
    update!(quantity_released: total)
    total
  end

  def unit_price
    return 0 if quantity.zero?
    case price_type
    when 'each'
      each_price || 0
    when 'lot'
      lot_price / quantity
    else
      0
    end
  end

  # Invoicing-related methods
  def can_be_invoiced?
    quantity_released > 0 && uninvoiced_release_notes.any?
  end

  def uninvoiced_release_notes
    release_notes.requires_invoicing
  end

  def invoiced_release_notes
    release_notes.joins(:invoice_item)
  end

  def total_uninvoiced_quantity
    uninvoiced_release_notes.sum(:quantity_accepted)
  end

  def total_invoiced_quantity
    invoiced_release_notes.sum(:quantity_accepted)
  end

  def fully_invoiced?
    quantity_released > 0 && uninvoiced_release_notes.empty?
  end

  def self.next_number
    Sequence.next_value('works_order_number')
  end

  def can_be_deleted?
    release_notes.empty?
  end

  private

  def set_defaults
    self.voided = false if voided.nil?
    self.is_open = true if is_open.nil?
    self.quantity_released = 0 if quantity_released.nil?
    self.part_issue = 'A' if part_issue.blank?
    self.price_type = 'each' if price_type.blank?
    self.customised_process_data = {} if customised_process_data.blank?
  end

  def assign_next_number
    self.number = self.class.next_number if number.blank?
  end

  def set_part_details_from_ppi
    return unless ppi

    self.part = ppi.part
    self.part_number = ppi.part_number
    self.part_issue = ppi.part_issue
    self.part_description = ppi.part_description if part_description.blank?
  end

  def normalize_part_details
    self.part_number = Part.make_uniform(part_number) if part_number.present?
    self.part_issue = Part.make_uniform(part_issue) if part_issue.present?
    self.part_issue = 'A' if part_issue.blank?
  end

  def pricing_fields_changed?
    quantity_changed? || lot_price_changed? || each_price_changed? || price_type_changed?
  end

  def calculate_pricing
    case price_type
    when 'each'
      if each_price.present? && quantity.present?
        self.lot_price = each_price * quantity
      end
    when 'lot'
      self.each_price = nil
    end
  end

  # AUTO-COMPLETION LOGIC
  def auto_complete_if_fully_released
    # Only check if quantity_released actually changed
    return unless quantity_released_previously_changed?

    # Auto-close if manufacturing is complete and still open
    if manufacturing_complete? && is_open?
      Rails.logger.info "🔒 AUTO-COMPLETE: Closing WO#{number} - all #{quantity} parts released"
      update_column(:is_open, false) # Use update_column to avoid triggering callbacks again
    end
  end
end
