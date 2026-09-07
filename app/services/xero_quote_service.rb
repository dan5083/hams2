# app/services/xero_quote_service.rb
#
# Changes:
#   - create_draft_quote takes an optional request_id: and attaches the
#     request's files itself. One tool call instead of two, so the assistant
#     can't stop after the quote and skip the attachment.
#   - attach_file retries on 404 (freshly created quote not yet visible to
#     the attachments endpoint).
#   - The 401s seen on 07/09 were the token-refresh rollback bug — fixed in
#     XeroToken, nothing to change here for that.
class XeroQuoteService
  require "net/http"
  require "uri"
  require "json"

  XERO_API_BASE = "https://api.xero.com/api.xro/2.0".freeze

  class RetryAttach < StandardError; end

  # Usage from AI assistant:
  #   XeroQuoteService.create_draft_quote(
  #     customer_name: "BG Developments",
  #     title: "...", summary: "...", reference: "...",
  #     line_items: [{ description: "...", quantity: 1, unit_amount: 250.00 }],
  #     request_id: @request_id   # attaches any drawings/PDFs from this run
  #   )
  def self.create_draft_quote(customer_name:, line_items:, title: nil, summary: nil, reference: nil, expiry_days: 30, request_id: nil)
    token = XeroToken.current
    raise "No active Xero connection. Ask someone to reconnect via Settings > Xero." unless token

    org = find_customer(customer_name)
    raise "Customer '#{customer_name}' not found in HAMS. Check the exact name." unless org
    raise "Customer '#{org.name}' has no Xero contact linked." unless org.xero_contact&.xero_id

    payload = {
      "Contact"         => { "ContactID" => org.xero_contact.xero_id },
      "Date"            => Date.current.iso8601,
      "ExpiryDate"      => (Date.current + expiry_days.days).iso8601,
      "Status"          => "DRAFT",
      "LineAmountTypes" => "Exclusive",
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

    res   = xero_post("#{XERO_API_BASE}/Quotes", { "Quotes" => [payload] }, token)
    quote = JSON.parse(res.body).dig("Quotes", 0)
    raise "No quote returned from Xero" unless quote

    result = {
      success:      true,
      quote_id:     quote["QuoteID"],
      quote_number: quote["QuoteNumber"],
      status:       quote["Status"],
      total:        quote["Total"],
      customer:     org.name,
      message:      "Draft quote #{quote['QuoteNumber']} created in Xero for #{org.name} — total £#{'%.2f' % quote['Total']} ex-VAT"
    }

    if request_id.present?
      attachment = attach_from_request(quote_id: quote["QuoteID"], request_id: request_id)
      result[:attachments] = attachment
      result[:message] += attachment[:success] ? " (#{attachment[:attached]} file(s) attached)" : " — attachment FAILED: #{attachment[:error]}"
    end

    result
  rescue => e
    Rails.logger.error "[XeroQuoteService] #{e.message}"
    { success: false, error: e.message }
  end

  # Attach every file from the request to the quote.
  def self.attach_from_request(quote_id:, request_id:)
    request = AiAssistantRequest.find(request_id)
    results = []

    request.messages.each do |msg|
      content = msg["content"]
      next unless content.is_a?(Array)

      content.each do |block|
        source = block["source"]
        next unless source&.dig("type") == "base64" && source["data"].present?

        media_type = source["media_type"] || "application/pdf"
        ext = case media_type
              when "application/pdf" then "pdf"
              when /image\/jpeg/     then "jpg"
              when /image\/png/      then "png"
              else "dat"
              end

        results << attach_file(
          quote_id:     quote_id,
          file_data:    source["data"],
          file_name:    "drawing_#{results.length + 1}.#{ext}",
          content_type: media_type
        )
      end
    end

    return { success: false, error: "No attachments found in the request messages." } if results.empty?

    failed = results.reject { |r| r[:success] }
    if failed.any?
      { success: false, attached: results.count { |r| r[:success] }, error: failed.map { |r| r[:error] }.uniq.join("; ") }
    else
      { success: true, attached: results.length, files: results.map { |r| r[:file_name] } }
    end
  rescue => e
    Rails.logger.error "[XeroQuoteService] attach_from_request error: #{e.message}"
    { success: false, error: e.message }
  end

  def self.attach_file(quote_id:, file_data:, file_name:, content_type: "application/pdf")
    token = XeroToken.current
    raise "No active Xero connection." unless token

    uri  = URI("#{XERO_API_BASE}/Quotes/#{quote_id}/Attachments/#{URI.encode_www_form_component(file_name)}")
    body = Base64.decode64(file_data)
    attempts = 0

    begin
      attempts += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Put.new(uri)
      req["Content-Type"] = content_type
      req["Accept"]       = "application/json"
      token.bearer_header.each { |k, v| req[k] = v }
      req.body = body

      res = http.request(req)

      if res.code == "404" && attempts < 4
        sleep(2**(attempts - 1))
        raise RetryAttach
      end

      unless res.is_a?(Net::HTTPSuccess)
        error = begin JSON.parse(res.body) rescue res.body end
        raise "Xero attachment error (#{res.code}): #{error}"
      end

      data = JSON.parse(res.body)
      { success: true, attachment_id: data.dig("Attachments", 0, "AttachmentID"), file_name: file_name }
    rescue RetryAttach
      retry
    end
  rescue => e
    Rails.logger.error "[XeroQuoteService] Attachment error: #{e.message}"
    { success: false, error: e.message }
  end

  private

  def self.find_customer(name)
    return nil if name.blank?
    clean = name.strip

    org = Organization.where("LOWER(name) = ?", clean.downcase).first
    return org if org

    org = Organization.where("name ILIKE ?", "#{clean}%").first
    return org if org

    Organization.where("name ILIKE ?", "%#{clean}%").order(Arel.sql("LENGTH(name)")).first
  end

  def self.xero_post(url, body, token)
    uri  = URI(url)
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
