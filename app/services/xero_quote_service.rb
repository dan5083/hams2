# app/services/xero_quote_service.rb
class XeroQuoteService
  require "net/http"
  require "uri"
  require "json"

  XERO_QUOTES_URL = "https://api.xero.com/api.xro/2.0/Quotes".freeze

  # Create a draft quote in Xero
  #
  # Usage from AI assistant:
  #   XeroQuoteService.create_draft_quote(
  #     customer_name: "BG Developments",
  #     line_items: [
  #       { description: "Hard Anodising 50µm — CP6910-131 (41 pcs)", quantity: 1, unit_amount: 245.00 },
  #       { description: "Hard Anodising 50µm — CT1132-1026 (1 pc)", quantity: 1, unit_amount: 250.00 }
  #     ],
  #     reference: "Quote for PO 15832",
  #     expiry_days: 30
  #   )
  #
  def self.create_draft_quote(customer_name:, line_items:, reference: nil, expiry_days: 30)
    token = XeroToken.current
    raise "No active Xero connection. Ask someone to reconnect via Settings > Xero." unless token

    # Look up the customer's Xero contact ID
    org = Organization.where("name ILIKE ?", "%#{customer_name}%").first
    raise "Customer '#{customer_name}' not found in HAMS." unless org
    raise "Customer '#{org.name}' has no Xero contact linked." unless org.xero_contact&.xero_id

    contact_id = org.xero_contact.xero_id

    # Build the quote payload
    payload = {
      "Contact"        => { "ContactID" => contact_id },
      "Date"           => Date.current.iso8601,
      "ExpiryDate"     => (Date.current + expiry_days.days).iso8601,
      "Status"         => "DRAFT",
      "LineAmountTypes" => "Exclusive",
      "Reference"      => reference,
      "CurrencyCode"   => "GBP",
      "LineItems"      => line_items.map { |item|
        {
          "Description" => item[:description],
          "Quantity"    => item[:quantity] || 1,
          "UnitAmount"  => item[:unit_amount].to_f.round(2),
          "TaxType"     => "OUTPUT2",
          "AccountCode" => item[:account_code] || "530514"
        }
      }
    }

    # POST to Xero
    uri = URI(XERO_QUOTES_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Accept"]       = "application/json"
    token.bearer_header.each { |k, v| req[k] = v }
    req.body = { "Quotes" => [payload] }.to_json

    res = http.request(req)

    unless res.is_a?(Net::HTTPSuccess)
      error = begin JSON.parse(res.body) rescue res.body end
      raise "Xero API error (#{res.code}): #{error}"
    end

    data = JSON.parse(res.body)
    quote = data.dig("Quotes", 0)
    raise "No quote returned from Xero" unless quote

    {
      success:      true,
      quote_id:     quote["QuoteID"],
      quote_number: quote["QuoteNumber"],
      status:       quote["Status"],
      total:        quote["Total"],
      customer:     org.name,
      message:      "Draft quote #{quote['QuoteNumber']} created in Xero for #{org.name} — total £#{'%.2f' % quote['Total']} ex-VAT"
    }
  rescue => e
    Rails.logger.error "[XeroQuoteService] #{e.message}"
    { success: false, error: e.message }
  end
end
