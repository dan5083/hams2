# app/models/invoice_item.rb
class InvoiceItem < ApplicationRecord
  belongs_to :invoice
  belongs_to :release_note, optional: true
  # belongs_to :additional_charge, optional: true # For future use

  validates :kind, inclusion: { in: %w[main additional manual] }
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :description, presence: true
  validates :line_amount_ex_tax, :line_amount_tax, :line_amount_inc_tax,
            presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation :calculate_tax_amounts, if: :line_amount_ex_tax_changed?
  before_validation :set_position, if: :new_record?
  after_save :update_invoice_totals
  after_destroy :update_invoice_totals

  scope :main_items, -> { where(kind: 'main') }
  scope :additional_items, -> { where(kind: 'additional') }
  scope :manual_items, -> { where(kind: 'manual') }

  def unit_price_ex_tax
    return 0 if quantity.zero?
    line_amount_ex_tax / quantity
  end

  def calculate_tax_amounts
    return unless invoice&.tax_rate_pct && line_amount_ex_tax

    tax_rate = invoice.tax_rate_pct / 100.0
    self.line_amount_tax = (line_amount_ex_tax * tax_rate).round(2)
    self.line_amount_inc_tax = line_amount_ex_tax + line_amount_tax
  end

  # Convert to Xero line item format
  def to_xero_line_item
    {
      "Description" => description,
      "Quantity" => quantity,
      "UnitAmount" => unit_price_ex_tax.to_f,
      "TaxType" => invoice.xero_tax_type,
      "LineAmount" => line_amount_ex_tax.to_f
    }
  end

  # Create invoice item from release note
  def self.create_from_release_note(release_note, invoice)
    return unless release_note.can_be_invoiced?

    item = new(
      invoice: invoice,
      release_note: release_note,
      kind: 'main',
      quantity: release_note.quantity_accepted,
      description: release_note.invoice_description,
      line_amount_ex_tax: release_note.invoice_value
    )

    # Tax will be calculated automatically
    item.save!
    item
  end

  private

  def set_position
    self.position = (invoice.invoice_items.maximum(:position) || -1) + 1
  end

  def update_invoice_totals
    invoice.calculate_totals
    invoice.save! if invoice.persisted?
  end
end
