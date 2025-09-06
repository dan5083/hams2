# app/models/invoice_item.rb
class InvoiceItem < ApplicationRecord
  belongs_to :invoice
  belongs_to :release_note, optional: true
  belongs_to :additional_charge_preset, optional: true

  # Match Mike's kind values exactly
  validates :kind, inclusion: { in: %w[main additional] }
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :description, presence: true
  validates :line_amount_ex_tax, :line_amount_tax, :line_amount_inc_tax,
            presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Ensure either release_note OR additional_charge_preset is present, not both
  validates :release_note_id, presence: true, if: -> { kind == 'main' }
  validates :additional_charge_preset_id, presence: true, if: -> { kind == 'additional' }
  validate :cannot_have_both_release_note_and_additional_charge

  before_validation :calculate_tax_amounts, if: :line_amount_ex_tax_changed?
  before_validation :set_position, if: :new_record?
  after_save :update_invoice_totals
  after_destroy :update_invoice_totals

  scope :main_items, -> { where(kind: 'main') }
  scope :additional_items, -> { where(kind: 'additional') }

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
      "LineAmount" => line_amount_ex_tax.to_f,
      "AccountCode" => "200" # Standard sales/revenue account code
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
      description: description_for_release_note(release_note),
      line_amount_ex_tax: release_note.invoice_value
    )

    item.save!
    item
  end

  # Create invoice item from additional charge preset
  def self.create_from_additional_charge(additional_charge_preset, invoice, custom_amount = nil)
    # Use custom amount for variable charges, preset amount for fixed charges
    amount = if additional_charge_preset.is_variable?
               custom_amount&.to_f || additional_charge_preset.amount || 0.0
             else
               additional_charge_preset.amount || 0.0
             end

    item = new(
      invoice: invoice,
      additional_charge_preset: additional_charge_preset,
      kind: 'additional',
      quantity: 1,
      description: additional_charge_preset.display_name,
      line_amount_ex_tax: amount
    )

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

  def cannot_have_both_release_note_and_additional_charge
    if release_note_id.present? && additional_charge_preset_id.present?
      errors.add(:base, "Cannot have both release note and additional charge preset")
    end
  end

  # Generate description for release note items
  def self.description_for_release_note(release_note)
    works_order = release_note.works_order
    customer_order = works_order.customer_order

    content_lines = [
      "Treatment of part #{works_order.part_number} (quantity: #{release_note.quantity_summary})",
      "Your order: #{customer_order.number}",
      "Our release note #{release_note.number} and works order #{works_order.number}."
    ]
    content_lines.join("\n\n")
  end
end
