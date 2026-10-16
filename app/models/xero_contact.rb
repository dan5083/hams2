# app/models/xero_contact.rb
#
# Mirror of a Xero contact. Two ways in:
#
#   1. The OAuth callback sync (XeroAuthController) — every contact in the
#      trading org, via upsert_from_api!.
#   2. The quote workbench — a customer the assistant couldn't match is
#      created IN XERO first (create_customer!) and then mirrored through the
#      same upsert_from_api!. There is deliberately no HAMS-only customer:
#      every Organization that can be quoted has a Xero contact behind it,
#      so the invoice can be raised later.
class XeroContact < ApplicationRecord
  XERO_API = "https://api.xero.com/api.xro/2.0".freeze

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

  # ── From the Xero API ───────────────────────────────────────────────────

  # One contact as the Xero API returns it (PascalCase keys) → XeroContact +
  # Organization. New organizations are enabled; existing ones keep their
  # enabled flag and get name/customer/supplier refreshed. Returns the
  # Organization.
  def self.upsert_from_api!(contact)
    xc = find_or_initialize_by(xero_id: contact["ContactID"])
    xc.assign_attributes(
      name:                         contact["Name"] || "Unknown",
      contact_status:               contact["ContactStatus"] || "ACTIVE",
      is_customer:                  contact["IsCustomer"] || false,
      is_supplier:                  contact["IsSupplier"] || false,
      accounts_receivable_tax_type: contact["AccountsReceivableTaxType"],
      accounts_payable_tax_type:    contact["AccountsPayableTaxType"],
      xero_data:                    contact,
      last_synced_at:               Time.current
    )
    xc.save!

    org = Organization.find_or_initialize_by(xero_contact: xc)
    org.enabled = true if org.new_record?
    org.assign_attributes(name: xc.name, is_customer: xc.is_customer, is_supplier: xc.is_supplier)
    org.save!

    if org.is_customer
      begin
        org.sync_address_from_xero!
      rescue => e
        Rails.logger.error "[XeroContact] Failed to sync address for #{org.name}: #{e.message}"
      end
    end
    org
  end

  # Create a customer in Xero and mirror it into HAMS. Xero contact names are
  # unique per org, so a contact already there under exactly this name is
  # adopted (and flagged IsCustomer if it wasn't) rather than failing with
  # Xero's "name is already assigned" validation error. The email goes on as
  # the contact's EmailAddress — Xero's invoicing address — because for a new
  # customer the enquirer is all we have; accounts can correct it in Xero.
  # Returns the Organization. Raises with Xero's message on any failure.
  def self.create_customer!(name:, email: nil)
    token = XeroToken.current or raise "HAMS isn't connected to Xero — connect via /auth/xero first"
    name  = name.to_s.strip
    raise "Customer name is blank" if name.blank?

    existing = xero_contacts(token, :get, params: { where: %(Name=="#{name.gsub('"', '\"')}") }).first
    contact =
      if existing.nil?
        body = { "Name" => name, "IsCustomer" => true }
        body["EmailAddress"] = email if email.present?
        Rails.logger.info "[XeroContact] Creating Xero customer #{name.inspect}"
        xero_contacts(token, :post, body: { "Contacts" => [body] }).first
      elsif existing["IsCustomer"]
        Rails.logger.info "[XeroContact] Adopting existing Xero contact #{name.inspect} (#{existing['ContactID']})"
        existing
      else
        Rails.logger.info "[XeroContact] Marking existing Xero contact #{name.inspect} as a customer"
        xero_contacts(token, :post, body: { "Contacts" => [existing.slice("ContactID").merge("IsCustomer" => true)] }).first
      end
    raise "Xero returned no contact for #{name.inspect}" unless contact.is_a?(Hash) && contact["ContactID"].present?

    upsert_from_api!(contact)
  end

  # GET or POST /Contacts with the stored token. POST creates, or updates
  # when a ContactID is given. Returns the Contacts array; raises with
  # Xero's validation message on a non-2xx.
  def self.xero_contacts(token, verb, params: {}, body: nil)
    uri = URI("#{XERO_API}/Contacts")
    uri.query = URI.encode_www_form(params) if params.any?

    req = (verb == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
    token.bearer_header.each { |k, v| req[k] = v }
    req["Accept"] = "application/json"
    if body
      req["Content-Type"] = "application/json"
      req.body = body.to_json
    end

    res  = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 30) { |h| h.request(req) }
    data = (JSON.parse(res.body) rescue {})
    unless res.is_a?(Net::HTTPSuccess)
      msg = Array(data.dig("Elements", 0, "ValidationErrors")).map { |e| e["Message"] }.join("; ").presence ||
            data["Detail"].presence || data["Message"].presence || res.body.to_s.first(300)
      raise "Xero contacts #{verb.to_s.upcase} failed (#{res.code}): #{msg}"
    end
    Array(data["Contacts"])
  end
  private_class_method :xero_contacts

  # ── Legacy demo sync (XeroService is still the stub) ───────────────────

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
    return unless organization

    organization.update!(
      name: name,
      is_customer: is_customer,
      is_supplier: is_supplier
    )
  end

  # ── Accessors over the stored Xero hash (PascalCase keys) ──────────────

  def primary_email
    email || xero_data&.dig("EmailAddress")
  end

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
