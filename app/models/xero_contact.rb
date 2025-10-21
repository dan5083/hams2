# app/models/xero_contact.rb
class XeroContact < ApplicationRecord
  has_one :organization, dependent: :destroy

  validates :name, presence: true
  validates :xero_id, presence: true, uniqueness: true
  validates :contact_status, inclusion: { in: %w[ACTIVE ARCHIVED GDPRREQUEST] }

  scope :customers, -> { where(is_customer: true) }
  scope :suppliers, -> { where(is_supplier: true) }
  scope :active, -> { where(contact_status: 'ACTIVE') }
  scope :needs_sync, -> { where('last_synced_at < ? OR last_synced_at IS NULL', 1.hour.ago) }

  # Store Xero data with easy access
  store_accessor :xero_data, :email, :phone, :website, :addresses, :contact_groups

  def self.sync_from_xero
    # This will connect to your Xero demo company
    xero_client = XeroService.new
    contacts = xero_client.get_contacts

    contacts.each do |xero_contact|
      sync_contact_from_xero(xero_contact)
    end
  end

  def self.sync_contact_from_xero(xero_contact)
    contact = find_or_initialize_by(xero_id: xero_contact.contact_id)

    contact.assign_attributes(
      name: xero_contact.name,
      contact_status: xero_contact.contact_status,
      is_customer: xero_contact.is_customer,
      is_supplier: xero_contact.is_supplier,
      accounts_receivable_tax_type: xero_contact.accounts_receivable_tax_type,
      accounts_payable_tax_type: xero_contact.accounts_payable_tax_type,
      xero_data: xero_contact.to_hash,
      last_synced_at: Time.current
    )

    contact.save!
    contact
  end

  def sync_to_organization
    return unless organisation

    organisation.update!(
      name: name,
      is_customer: is_customer,
      is_supplier: is_supplier
    )
  end

  # FIXED: Xero uses PascalCase keys, not snake_case
  def primary_email
    email || xero_data&.dig("EmailAddress")  # Changed from 'email_address' to "EmailAddress"
  end

  # FIXED: Extract phone from Xero's Phones array structure
  def primary_phone
    return phone if phone.present?

    phones = xero_data&.dig("Phones")
    return nil unless phones

    # Get DEFAULT phone first, fallback to DDI or first available
    default_phone = phones.find { |p| p["PhoneType"] == "DEFAULT" } ||
                    phones.find { |p| p["PhoneType"] == "DDI" } ||
                    phones.first

    return nil unless default_phone && default_phone["PhoneNumber"].present?

    area = default_phone["PhoneAreaCode"]
    number = default_phone["PhoneNumber"]
    [area, number].compact.join(" ")
  end

  # FIXED: Extract address from Xero's Addresses array structure
  def primary_address
    return addresses if addresses.present?

    xero_addresses = xero_data&.dig("Addresses")
    return nil unless xero_addresses

    # Prefer POBOX, then STREET
    address = xero_addresses.find { |a| a["AddressType"] == "POBOX" } ||
              xero_addresses.find { |a| a["AddressType"] == "STREET" }

    return nil unless address

    parts = []
    parts << address["AddressLine1"] if address["AddressLine1"].present?
    parts << address["AddressLine2"] if address["AddressLine2"].present?
    parts << address["AddressLine3"] if address["AddressLine3"].present?
    parts << address["AddressLine4"] if address["AddressLine4"].present?

    # Add city, region, postal code
    location_parts = []
    location_parts << address["City"] if address["City"].present?
    location_parts << address["Region"] if address["Region"].present?
    location_parts << address["PostalCode"] if address["PostalCode"].present?
    parts << location_parts.join(", ") if location_parts.any?

    parts.join("\n")
  end

  def merged?
    merged_to_contact_id.present?
  end

  def active?
    contact_status == 'ACTIVE'
  end
end
