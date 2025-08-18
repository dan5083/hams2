# app/services/xero_invoice_service.rb
class XeroInvoiceService
  include ActionView::Helpers::TextHelper

  def initialize(token_set, tenant_id)
    @token_set = token_set
    @tenant_id = tenant_id
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

      # Update invoice with Xero response
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

      {
        success: false,
        error: e.message,
        message: "Failed to create invoice in Xero: #{e.message}"
      }
    end
  end

  # Fetch invoice from Xero (to sync back status/payment info)
  def fetch_invoice(xero_invoice_id)
    Rails.logger.info "📥 Fetching invoice #{xero_invoice_id} from Xero..."

    begin
      response_data = get_invoice_from_xero(xero_invoice_id)

      {
        success: true,
        invoice_data: response_data
      }

    rescue => e
      Rails.logger.error "❌ Failed to fetch invoice from Xero: #{e.message}"

      {
        success: false,
        error: e.message
      }
    end
  end

  # Push multiple invoices in batch
  def push_invoices_batch(invoices)
    results = []

    invoices.each do |invoice|
      result = push_invoice(invoice)
      results << {
        invoice_id: invoice.id,
        local_number: invoice.display_name,
        **result
      }

      # Small delay to avoid rate limiting
      sleep(0.5) if invoices.count > 1
    end

    successful_count = results.count { |r| r[:success] }

    {
      total: results.count,
      successful: successful_count,
      failed: results.count - successful_count,
      results: results
    }
  end

  # Get all invoices requiring Xero sync
  def self.get_invoices_requiring_sync
    Invoice.requiring_xero_sync.includes(:customer, :invoice_items)
  end

  private

  def create_invoice_in_xero(payload)
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI("https://api.xero.com/api.xro/2.0/Invoices")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token_set['access_token']}"
    request['xero-tenant-id'] = @tenant_id
    request['Accept'] = 'application/json'
    request['Content-Type'] = 'application/json'
    request.body = { "Invoices" => [payload] }.to_json

    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      if data['Invoices']&.any?
        return data['Invoices'].first
      else
        raise "No invoice returned in response"
      end
    else
      error_detail = begin
        JSON.parse(response.body)
      rescue
        response.body
      end
      raise "API call failed with status #{response.code}: #{error_detail}"
    end
  end

  def get_invoice_from_xero(invoice_id)
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI("https://api.xero.com/api.xro/2.0/Invoices/#{invoice_id}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@token_set['access_token']}"
    request['xero-tenant-id'] = @tenant_id
    request['Accept'] = 'application/json'

    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      return data['Invoices']&.first
    else
      raise "API call failed with status #{response.code}: #{response.body}"
    end
  end
end
