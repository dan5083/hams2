# app/models/organization.rb
class Organization < ApplicationRecord
  belongs_to :xero_contact, optional: true

  # Future associations (we'll add these as we build the system)
  # has_many :parts, foreign_key: :customer_id
  # has_many :customer_orders, foreign_key: :customer_id
  # has_many :works_orders, through: :customer_orders
  has_many :invoices, foreign_key: :customer_id, dependent: :restrict_with_error

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

      # Sync address for customers
      if organization.is_customer
        organization.sync_address_from_xero!
      end
    end
  end

  # Sync address from Xero contact data
  def sync_address_from_xero!
    return unless is_customer && xero_contact&.xero_data.present?

    addresses = xero_contact.xero_data['Addresses']
    return unless addresses.present?

    # Look for POBOX first, then STREET address
    address = addresses.find { |addr| addr['AddressType'] == 'POBOX' } ||
              addresses.find { |addr| addr['AddressType'] == 'STREET' } ||
              addresses.first

    if address.present?
      # Format the address from Xero data
      address_parts = []
      address_parts << address['AttentionTo'] if address['AttentionTo'].present?
      address_parts << address['AddressLine1'] if address['AddressLine1'].present?
      address_parts << address['AddressLine2'] if address['AddressLine2'].present?
      address_parts << address['AddressLine3'] if address['AddressLine3'].present?
      address_parts << address['AddressLine4'] if address['AddressLine4'].present?

      # Add city/region/postal
      location_parts = []
      location_parts << address['City'] if address['City'].present?
      location_parts << address['Region'] if address['Region'].present?
      location_parts << address['PostalCode'] if address['PostalCode'].present?

      address_parts << location_parts.join(' ') if location_parts.any?
      address_parts << address['Country'] if address['Country'].present?

      if address_parts.any?
        update!(address_data: address_parts.join("\n"))
        return true
      end
    end

    false
  end

  # Address methods for customers
  def formatted_address
    return nil unless is_customer && address_data.present?
    address_data.to_s
  end

  # Check if customer has an address set
  def has_address?
    is_customer && address_data.present?
  end

  # For PDF generation - returns formatted address or a default message
  def pdf_address
    has_address? ? formatted_address : "Address not on file"
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
    # Keep this method for backward compatibility, but prefer pdf_address for PDFs
    xero_contact&.primary_address
  end

  # NEW: Get buyer emails for order acknowledgements
  # Returns array of buyer emails from Xero contact persons with "Include in emails" enabled
  # Falls back to primary contact email if no buyers configured
  def buyer_emails
    return [] unless xero_contact

    emails = xero_contact.buyer_emails

    # If no buyer emails configured, fall back to primary contact email
    if emails.empty?
      primary = contact_email
      return primary.present? ? [primary] : []
    end

    emails
  end

  # Helper to get buyer contact details for display/debugging
  def buyer_contacts
    xero_contact&.buyer_contacts || []
  end

  # Check if this customer has buyers configured
  def has_buyers?
    xero_contact&.buyer_emails&.any? || false
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

  # Class method to sync all customer addresses from Xero
  def self.sync_all_customer_addresses!
    customers.includes(:xero_contact).find_each do |customer|
      begin
        customer.sync_address_from_xero!
      rescue => e
        Rails.logger.error "Failed to sync address for customer #{customer.name}: #{e.message}"
      end
    end
  end

  private

  def set_defaults
    self.enabled = true if enabled.nil?
    self.is_customer = false if is_customer.nil?
    self.is_supplier = false if is_supplier.nil?
  end
end
