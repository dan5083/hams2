# app/models/release_note.rb - Verified and enhanced for invoicing
class ReleaseNote < ApplicationRecord
  belongs_to :works_order
  belongs_to :issued_by, class_name: 'User'
  has_one :invoice_item, dependent: :nullify

  validates :date, presence: true
  validates :quantity_accepted, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_rejected, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validate :total_quantity_must_be_positive
  validate :quantity_available_for_release

  scope :active, -> { where(voided: false) }
  scope :voided, -> { where(voided: true) }

  # VERIFIED: This scope correctly identifies release notes that need invoicing
  scope :requires_invoicing, -> {
    left_joins(:invoice_item)
      .where(invoice_items: { id: nil })          # No invoice item exists
      .where(voided: false)                       # Not voided
      .where('quantity_accepted > 0')             # Has accepted quantity
      .where.not(no_invoice: true)                # Not marked as no_invoice
  }

  # NEW: Additional useful scopes for invoicing workflow
  scope :invoiced, -> { joins(:invoice_item) }
  scope :ready_for_invoice, -> { requires_invoicing }  # Alias for clarity
  scope :recent, -> { order(number: :desc) }

  before_validation :set_date, if: :new_record?
  before_validation :assign_next_number, if: :new_record?
  after_initialize :set_defaults, if: :new_record?
  after_save :update_works_order_quantity_released
  after_destroy :update_works_order_quantity_released

  def display_name
    "RN#{number}"
  end

  # Delegate customer info to works_order
  def customer
    works_order.customer
  end

  def invoice_customer_name
    works_order.invoice_customer_name
  end

  def invoice_address
    works_order.invoice_address
  end

  def delivery_customer_name
    works_order.delivery_customer_name
  end

  def delivery_address
    works_order.delivery_address
  end

  def specification
    works_order.specification
  end

  def release_statement
    return '' unless works_order.release_level&.statement && specification
    works_order.release_level.statement.gsub('[SPECIFICATION]', specification)
  end

  def total_quantity
    quantity_accepted + quantity_rejected
  end

  def quantity_summary
    if quantity_rejected > 0
      "#{quantity_accepted} accepted, #{quantity_rejected} rejected"
    else
      quantity_accepted.to_s
    end
  end

  def void!
    transaction do
      if invoice_item.present?
        raise StandardError, "Cannot void release note that has been invoiced"
      end
      update!(voided: true)
    end
  end

  def can_be_voided?
    invoice_item.blank?
  end

  def can_be_invoiced?
    !voided && quantity_accepted > 0 && !no_invoice
  end

  # NEW: Enhanced invoicing status methods
  def invoiced?
    invoice_item.present?
  end

  def ready_for_invoice?
    can_be_invoiced? && invoice_item.blank?
  end

  def invoice_status
    return :voided if voided
    return :invoiced if invoiced?
    return :ready if ready_for_invoice?
    return :no_invoice if no_invoice
    :unknown
  end

  def invoice_description
    "#{works_order.part_number}-#{works_order.part_issue} x #{quantity_accepted}"
  end

  def invoice_value
    case works_order.price_type
    when 'each'
      quantity_accepted * (works_order.each_price || 0)
    when 'lot'
      # For lot pricing, we need to calculate proportionally
      return 0 if works_order.quantity.zero?
      (quantity_accepted.to_f / works_order.quantity) * works_order.lot_price
    else
      0
    end
  end

  def self.next_number
    Sequence.next_value('release_note_number')
  end

  def can_be_deleted?
    invoice_item.blank?
  end

  private

  def set_defaults
    self.voided = false if voided.nil?
    self.quantity_accepted = 0 if quantity_accepted.nil?
    self.quantity_rejected = 0 if quantity_rejected.nil?
    self.no_invoice = false if no_invoice.nil?
  end

  def set_date
    self.date = Date.current if date.blank?
  end

  def assign_next_number
    self.number = self.class.next_number if number.blank?
  end

  def total_quantity_must_be_positive
    if total_quantity <= 0
      errors.add(:base, "Total quantity (accepted + rejected) must be greater than 0")
    end
  end

  def quantity_available_for_release
    return unless works_order && total_quantity

    # Calculate how much quantity this release note currently accounts for
    current_quantity = persisted? ? quantity_accepted_was + quantity_rejected_was : 0

    # Calculate the additional quantity this release note would account for
    additional_quantity = total_quantity - current_quantity

    # Only check if we're increasing the total quantity released
    if additional_quantity > 0 && additional_quantity > works_order.quantity_remaining
      errors.add(:base,
        "You are trying to release #{additional_quantity} parts, " \
        "but only #{works_order.quantity_remaining} are available for release."
      )
    end
  end

  def update_works_order_quantity_released
    works_order&.calculate_quantity_released!
  end
end
