# app/services/xero_service.rb
require 'ostruct'

class XeroService
  def initialize
    # We'll set up the real Xero client later
    # For now, just return demo data
  end

  def get_contacts
    # Return demo data that matches what Xero API would return
    demo_contacts
  end

  private

  def demo_contacts
    [
      OpenStruct.new(
        contact_id: "demo-1",
        name: "Acme Manufacturing Ltd",
        contact_status: "ACTIVE",
        is_customer: true,
        is_supplier: false,
        accounts_receivable_tax_type: "OUTPUT",
        accounts_payable_tax_type: nil,
        to_hash: {
          "contact_id" => "demo-1",
          "name" => "Acme Manufacturing Ltd",
          "email_address" => "accounts@acme.com",
          "phones" => [{ "phone_number" => "01234 567890" }]
        }
      ),
      OpenStruct.new(
        contact_id: "demo-2",
        name: "Precision Engineering Co",
        contact_status: "ACTIVE",
        is_customer: true,
        is_supplier: false,
        accounts_receivable_tax_type: "OUTPUT",
        accounts_payable_tax_type: nil,
        to_hash: {
          "contact_id" => "demo-2",
          "name" => "Precision Engineering Co",
          "email_address" => "orders@precision-eng.co.uk",
          "phones" => [{ "phone_number" => "0161 123 4567" }]
        }
      )
    ]
  end
end
