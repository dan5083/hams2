# app/models/invoice.rb - FIXED number assignment timing
class Invoice < ApplicationRecord
  belongs_to :customer, class_name: 'Organization'
  has_many :invoice_items, dependent: :destroy

  validates :number, presence: true
  validates :date, presence: true
  validates :tax_rate_pct, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :xero_tax_type, presence: true

  # Financial validations - exactly matching Mike's fields
  validates :total_ex_tax, :total_tax, :total_inc_tax,
            presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Scopes exactly like Mike's - no status, just Xero sync tracking
  scope :synced, -> { where.not(xero_id: nil) }
  scope :requiring_xero_sync, -> { where(xero_id: nil) }
  scope :recent, -> { order(date: :desc) }

  # For dashboard compatibility - treat all as "draft" until synced like Mike did
  scope :draft, -> { all }

  before_validation :set_defaults, if: :new_record?
  before_validation :assign_next_number, if: :new_record?  # MOVED: Now runs before validation
  after_initialize :set_defaults, if: :new_record?

  def display_name
    "INV#{number}"
  end

  def self.next_number
    Sequence.next_value('invoice_number')
  end

  # Exactly like Mike's calculate_totals
  def calculate_totals
    self.total_ex_tax = invoice_items.sum(:line_amount_ex_tax)
    self.total_tax = invoice_items.sum(:line_amount_tax)
    self.total_inc_tax = total_ex_tax + total_tax
  end

  def calculate_totals!
    calculate_totals
    save! if persisted?
  end

  # Simple like Mike's - just track Xero sync
  def synced_with_xero?
    xero_id.present?
  end

  def requires_xero_sync?
    xero_id.blank?
  end

  def xero_url
    return unless xero_id
    "https://go.xero.com/AccountsReceivable/View.aspx?InvoiceID=#{xero_id}"
  end

  # Mike's Xero format - simple AUTHORISED status
  def to_xero_invoice
    {
      "Type" => "ACCREC",
      "Contact" => {
        "ContactID" => customer.xero_contact&.xero_id
      },
      "InvoiceNumber" => display_name,
      "Date" => date.strftime("%Y-%m-%d"),
      "DueDate" => (date + 30.days).strftime("%Y-%m-%d"), # Add 30 days payment terms
      "LineItems" => invoice_items.map(&:to_xero_line_item),
      "Status" => "AUTHORISED"
    }.compact
  end

  # Methods for XeroInvoiceService compatibility
  def can_be_pushed_to_xero?
    requires_xero_sync? && customer.xero_contact&.xero_id.present?
  end

  def update_from_xero_response(response_data)
    update!(xero_id: response_data['InvoiceID']) if response_data['InvoiceID']
  end

  # Mike's creation method from release notes
  def self.create_from_release_notes(release_notes, customer, user = nil)
    return nil if release_notes.empty?

    customer_ids = release_notes.map { |rn| rn.customer.id }.uniq
    if customer_ids.length > 1
      raise StandardError, "All release notes must be for the same customer"
    end

    unless release_notes.all?(&:can_be_invoiced?)
      raise StandardError, "Some release notes cannot be invoiced"
    end

    invoice = new(customer: customer, date: Date.current)

    if invoice.save
      release_notes.each do |release_note|
        InvoiceItem.create_from_release_note(release_note, invoice)
      end
      invoice.calculate_totals!
      invoice
    else
      nil
    end
  end

  private

  def set_defaults
    self.date = Date.current if date.blank?
    self.tax_rate_pct = 20.0 if tax_rate_pct.blank? # UK VAT rate
    self.xero_tax_type = 'OUTPUT2' if xero_tax_type.blank? # UK standard rate
    self.total_ex_tax = 0.0 if total_ex_tax.blank?
    self.total_tax = 0.0 if total_tax.blank?
    self.total_inc_tax = 0.0 if total_inc_tax.blank?
  end

  def assign_next_number
    self.number = self.class.next_number if number.blank?
  end
end
