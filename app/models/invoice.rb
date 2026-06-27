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
  scope :draft, -> { where(xero_id: nil) }

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
      "Status" => "SUBMITTED"
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

  # ---------------------------------------------------------------------------
  # Stage an invoice for whatever release notes still require invoicing in the
  # given relation/array ("to date" semantics — partial orders are fine).
  #
  # Courier (additional) charges are billed ONE PER RELEASE NOTE — each release
  # is a dispatch, so n releases on a WO produce n courier lines. Idempotency is
  # structural: the batch is always requires_invoicing release notes (no main
  # line item yet), and once invoiced they leave that scope permanently, so a
  # release note's part line AND its courier line are each billed exactly once.
  #
  # The courier amount comes from the works order's custom_amounts entry, so
  # every release on a WO bills the SAME (flat) carriage figure. If carriage
  # ever needs to vary per dispatch, that amount has to move onto the release
  # note itself.
  #
  # Returns the Invoice, or nil if there was nothing left to invoice.
  # ---------------------------------------------------------------------------
  def self.stage_to_date(release_notes, user = nil)
    release_notes = release_notes.to_a
    return nil if release_notes.empty? # caller shows "nothing to invoice"

    transaction do
      customer = release_notes.first.customer
      invoice  = create_from_release_notes(release_notes, customer, user)
      raise StandardError, "Invoice failed to save" if invoice.nil?

      # One courier charge per release note in this batch.
      release_notes.each do |rn|
        wo = rn.works_order
        next if wo.nil? || wo.selected_charge_ids.blank?

        custom_amounts = wo.custom_amounts || {}
        wo.selected_charge_ids.reject(&:blank?).each do |charge_id|
          charge = AdditionalChargePreset.find(charge_id)
          InvoiceItem.create_from_additional_charge(charge, invoice, custom_amounts[charge_id], rn)
        end
      end

      invoice.calculate_totals!
      invoice
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
