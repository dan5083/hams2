# app/services/xero_invoice_service.rb
class XeroInvoiceService
  include ActionView::Helpers::TextHelper

  XERO_API_BASE = "https://api.xero.com/api.xro/2.0".freeze

  def initialize(token_set, tenant_id)
    @token_set = token_set
    @tenant_id = tenant_id
  end

  # For job/assistant contexts with no session — uses the stored, auto-
  # refreshing XeroToken. (Controllers still pass the session token set.)
  def self.from_current_token
    token = XeroToken.current
    raise "No active Xero connection. Reconnect via Settings > Xero." unless token
    new({ "access_token" => token.access_token }, token.tenant_id)
  end

  # Push invoice to Xero (create new invoice)
  def push_invoice(invoice)
    raise ArgumentError, "Invoice must be in draft status" unless invoice.can_be_pushed_to_xero?
    raise ArgumentError, "Customer must have Xero contact" unless invoice.customer.xero_contact&.xero_id

    Rails.logger.info "🚀 Pushing invoice #{invoice.id} to Xero..."

    begin
      payload = invoice.to_xero_invoice
      Rails.logger.info "Payload: #{payload.to_json}"

      response_data = create_invoice_in_xero(payload)
      invoice.update_from_xero_response(response_data)

      Rails.logger.info "✅ Successfully pushed invoice #{invoice.display_name} to Xero"

      {
        success: true,
        invoice_id: response_data['InvoiceID'],
        invoice_number: response_data['InvoiceNumber'],
        message: "Invoice #{response_data['InvoiceNumber']} created in Xero"
      }
    rescue => e
      Rails.logger.error "❌ Failed to push invoice to Xero: #{e.message}"
      { success: false, error: e.message, message: "Failed to create invoice in Xero: #{e.message}" }
    end
  end

  # Fetch invoice from Xero (to sync back status/payment info)
  def fetch_invoice(xero_invoice_id)
    Rails.logger.info "📥 Fetching invoice #{xero_invoice_id} from Xero..."
    { success: true, invoice_data: get_invoice_from_xero(xero_invoice_id) }
  rescue => e
    Rails.logger.error "❌ Failed to fetch invoice from Xero: #{e.message}"
    { success: false, error: e.message }
  end

  # Attach a file to an existing Xero invoice.
  #   PUT /Invoices/{InvoiceID}/Attachments/{FileName}
  # `include_online: true` makes it visible to the customer on the online
  # invoice — off by default for internal evidence like a PoC.
  #
  # Retries on 404: Xero can briefly 404 the attachments endpoint for an
  # invoice created a moment ago.
  def attach_file(invoice_id:, file_bytes:, file_name:, content_type: "application/pdf", include_online: false)
    raise ArgumentError, "invoice_id required" if invoice_id.blank?

    uri = URI("#{XERO_API_BASE}/Invoices/#{invoice_id}/Attachments/#{URI.encode_www_form_component(file_name)}")
    uri.query = "IncludeOnline=true" if include_online

    attempts = 0
    begin
      attempts += 1
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Put.new(uri)
      req["Content-Type"] = content_type
      req["Accept"]       = "application/json"
      auth_headers.each { |k, v| req[k] = v }
      req.body = file_bytes

      res = http.request(req)

      if res.code == "404" && attempts < 4
        sleep(2**(attempts - 1)) # 1s, 2s, 4s
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
    Rails.logger.error "[XeroInvoiceService] Attachment error: #{e.message}"
    { success: false, error: e.message }
  end

  # Push multiple invoices in batch
  def push_invoices_batch(invoices)
    results = []
    invoices.each do |invoice|
      result = push_invoice(invoice)
      results << { invoice_id: invoice.id, local_number: invoice.display_name, **result }
      sleep(0.5) if invoices.count > 1
    end
    successful_count = results.count { |r| r[:success] }
    { total: results.count, successful: successful_count, failed: results.count - successful_count, results: results }
  end

  def self.get_invoices_requiring_sync
    Invoice.requiring_xero_sync.includes(:customer, :invoice_items)
  end

  private

  class RetryAttach < StandardError; end

  def auth_headers
    { "Authorization" => "Bearer #{@token_set['access_token']}", "xero-tenant-id" => @tenant_id }
  end

  def create_invoice_in_xero(payload)
    uri  = URI("#{XERO_API_BASE}/Invoices")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    auth_headers.each { |k, v| request[k] = v }
    request['Accept']       = 'application/json'
    request['Content-Type'] = 'application/json'
    request.body = { "Invoices" => [payload] }.to_json

    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      data['Invoices']&.first or raise "No invoice returned in response"
    else
      error_detail = begin JSON.parse(response.body) rescue response.body end
      raise "API call failed with status #{response.code}: #{error_detail}"
    end
  end

  def get_invoice_from_xero(invoice_id)
    uri  = URI("#{XERO_API_BASE}/Invoices/#{invoice_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    auth_headers.each { |k, v| request[k] = v }
    request['Accept'] = 'application/json'

    response = http.request(request)
    if response.code == '200'
      JSON.parse(response.body)['Invoices']&.first
    else
      raise "API call failed with status #{response.code}: #{response.body}"
    end
  end
end
