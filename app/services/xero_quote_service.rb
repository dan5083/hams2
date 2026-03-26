# app/services/xero_quote_service.rb
class XeroQuoteService
  require "net/http"
  require "uri"
  require "json"

  XERO_API_BASE = "https://api.xero.com/api.xro/2.0".freeze

  # Create a draft quote in Xero
  #
  # Usage from AI assistant:
  #   XeroQuoteService.create_draft_quote(
  #     customer_name: "BG Developments",
  #     title: "PD67711-00 — Door Upper Hinge Insert",
  #     summary: "Standard Anodising Type II DEF-STAN 03-25, 10–15µm, Clear",
  #     reference: "enquirer@example.com",
  #     line_items: [
  #       { description: "Standard Anodising — Door Upper Hinge Insert (50 pcs)", quantity: 1, unit_amount: 250.00 }
  #     ],
  #     expiry_days: 30
  #   )
  #
  def self.create_draft_quote(customer_name:, line_items:, title: nil, summary: nil, reference: nil, expiry_days: 30)
    token = XeroToken.current
    raise "No active Xero connection. Ask someone to reconnect via Settings > Xero." unless token

    # Look up the customer — exact match first, then progressively looser
    org = find_customer(customer_name)
    raise "Customer '#{customer_name}' not found in HAMS. Check the exact name." unless org
    raise "Customer '#{org.name}' has no Xero contact linked." unless org.xero_contact&.xero_id

    contact_id = org.xero_contact.xero_id

    # Build the quote payload
    payload = {
      "Contact"         => { "ContactID" => contact_id },
      "Date"            => Date.current.iso8601,
      "ExpiryDate"      => (Date.current + expiry_days.days).iso8601,
      "Status"          => "DRAFT",
      "LineAmountTypes"  => "Exclusive",
      "CurrencyCode"    => "GBP",
      "Title"           => title,
      "Summary"         => summary,
      "Reference"       => reference,
      "LineItems"       => line_items.map { |item|
        {
          "Description" => item[:description],
          "Quantity"    => item[:quantity] || 1,
          "UnitAmount"  => item[:unit_amount].to_f.round(2),
          "TaxType"     => "OUTPUT2",
          "AccountCode" => item[:account_code] || "530514"
        }
      }
    }.compact

    # POST to Xero
    res = xero_post("#{XERO_API_BASE}/Quotes", { "Quotes" => [payload] }, token)

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

  # Attach a file (PDF/image) to an existing Xero quote
  #
  # Usage from AI assistant:
  #   XeroQuoteService.attach_file(
  #     quote_id: "abc-123-...",
  #     file_data: "<base64 encoded data>",
  #     file_name: "drawing.pdf",
  #     content_type: "application/pdf"
  #   )
  #
  def self.attach_file(quote_id:, file_data:, file_name:, content_type: "application/pdf")
    token = XeroToken.current
    raise "No active Xero connection." unless token

    uri = URI("#{XERO_API_BASE}/Quotes/#{quote_id}/Attachments/#{URI.encode_www_form_component(file_name)}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Put.new(uri)
    req["Content-Type"] = content_type
    req["Accept"]       = "application/json"
    token.bearer_header.each { |k, v| req[k] = v }

    # Decode base64 to binary
    req.body = Base64.decode64(file_data)

    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      error = begin JSON.parse(res.body) rescue res.body end
      raise "Xero attachment error (#{res.code}): #{error}"
    end

    data = JSON.parse(res.body)
    { success: true, attachment_id: data.dig("Attachments", 0, "AttachmentID"), file_name: file_name }
  rescue => e
    Rails.logger.error "[XeroQuoteService] Attachment error: #{e.message}"
    { success: false, error: e.message }
  end

  private

  # Find customer with progressively looser matching
  def self.find_customer(name)
    return nil if name.blank?
    clean = name.strip

    # 1. Exact match (case-insensitive)
    org = Organization.where("LOWER(name) = ?", clean.downcase).first
    return org if org

    # 2. Starts with
    org = Organization.where("name ILIKE ?", "#{clean}%").first
    return org if org

    # 3. Contains (last resort)
    Organization.where("name ILIKE ?", "%#{clean}%")
                .order(Arel.sql("LENGTH(name)"))
                .first
  end

  def self.xero_post(url, body, token)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req["Accept"]       = "application/json"
    token.bearer_header.each { |k, v| req[k] = v }
    req.body = body.to_json

    res = http.request(req)
    unless res.is_a?(Net::HTTPSuccess)
      error = begin JSON.parse(res.body) rescue res.body end
      raise "Xero API error (#{res.code}): #{error}"
    end
    res
  end
end
