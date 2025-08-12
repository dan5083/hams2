class Organization < ApplicationRecord
  belongs_to :xero_contact, optional: true

  # Future associations (we'll add these as we build the system)
  # has_many :parts, foreign_key: :customer_id
  # has_many :customer_orders, foreign_key: :customer_id
  # has_many :works_orders, through: :customer_orders
  # has_many :invoices, foreign_key: :customer_id

  validates :name, presence: true
  validates :is_customer, inclusion: { in: [true, false] }
  validates :is_supplier, inclusion: { in: [true, false] }

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :customers, -> { where(is_customer: true) }
  scope :suppliers, -> { where(is_supplier: true) }
  scope :with_xero, -> { joins(:xero_contact) }
  scope :without_xero, -> { where(xero_contact: nil) }

  # Default enabled to true for new organizations
  after_initialize :set_defaults, if: :new_record?

  def self.sync_from_xero
    XeroContact.sync_from_xero

    # Create or update organizations for each Xero contact
    XeroContact.active.each do |xero_contact|
      organization = find_or_create_by(xero_contact: xero_contact) do |org|
        org.name = xero_contact.name
        org.is_customer = xero_contact.is_customer
        org.is_supplier = xero_contact.is_supplier
        org.enabled = true
      end

      # Update existing organizations
      organization.update!(
        name: xero_contact.name,
        is_customer: xero_contact.is_customer,
        is_supplier: xero_contact.is_supplier
      )
    end
  end

  def display_name
    name
  end

  def contact_email
    xero_contact&.primary_email
  end

  def contact_phone
    xero_contact&.primary_phone
  end

  def contact_address
    xero_contact&.primary_address
  end

  def synced_with_xero?
    xero_contact.present?
  end

  def xero_url
    return unless xero_contact&.xero_id
    "https://go.xero.com/Contacts/View/#{xero_contact.xero_id}"
  end

  def active?
    enabled && (!xero_contact || xero_contact.active?)
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.is_customer = false if is_customer.nil?
    self.is_supplier = false if is_supplier.nil?
  end
end
