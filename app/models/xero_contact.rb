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

  def primary_email
    email || xero_data.dig('email_address')
  end

  def primary_phone
    phone || xero_data.dig('phones', 0, 'phone_number')
  end

  def primary_address
    addresses&.first || xero_data.dig('addresses', 0)
  end

  def merged?
    merged_to_contact_id.present?
  end

  def active?
    contact_status == 'ACTIVE'
  end
end
