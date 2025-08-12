class XeroAuthController < ApplicationController
  def authorize
    # Initialize Xero client for OAuth
    creds = {
      client_id: ENV['XERO_CLIENT_ID'] || Rails.application.credentials.dig(:xero, :client_id),
      client_secret: ENV['XERO_CLIENT_SECRET'] || Rails.application.credentials.dig(:xero, :client_secret),
      redirect_uri: ENV['XERO_REDIRECT_URI'] || Rails.application.credentials.dig(:xero, :redirect_uri),
      scopes: 'accounting.contacts accounting.transactions offline_access'
    }

    xero_client = XeroRuby::ApiClient.new(credentials: creds)

    # Get authorization URL and redirect user to Xero
    auth_url = xero_client.authorization_url
    redirect_to auth_url, allow_other_host: true
  end

  def callback
    # Handle the callback from Xero with authorization code
    auth_code = params[:code]

    if auth_code.blank?
      redirect_to root_path, alert: "Xero authorization failed"
      return
    end

    begin
      # Exchange authorization code for access token
      creds = {
        client_id: ENV['XERO_CLIENT_ID'] || Rails.application.credentials.dig(:xero, :client_id),
        client_secret: ENV['XERO_CLIENT_SECRET'] || Rails.application.credentials.dig(:xero, :client_secret),
        redirect_uri: ENV['XERO_REDIRECT_URI'] || Rails.application.credentials.dig(:xero, :redirect_uri)
      }

      xero_client = XeroRuby::ApiClient.new(credentials: creds)

      # Set the authorization code first, then get the token set
      token_set = xero_client.get_token_set_from_callback(params)

      # CHECK: Ensure token_set is valid
      Rails.logger.info "Token set received: #{token_set.keys}"

      if token_set.key?('error')
        Rails.logger.error "Token error: #{token_set}"
        redirect_to root_path, alert: "Token error: #{token_set['error']}"
        return
      end

      # CRITICAL: Set the token set on the client BEFORE calling connections
      xero_client.set_token_set(token_set)

      # Get available tenants (companies) - NOW with authenticated client
      connections = xero_client.connections

      # Check if connections returned an error
      if connections.is_a?(Hash) && connections.key?('error')
        Rails.logger.error "Connections error: #{connections}"
        redirect_to root_path, alert: "Failed to get organizations: #{connections['error']}"
        return
      end

      if connections.empty?
        redirect_to root_path, alert: "No Xero organizations found"
        return
      end

      # Log all available tenants
      Rails.logger.info "Available Xero tenants:"
      connections.each do |connection|
        Rails.logger.info "- Name: '#{connection['tenantName']}', ID: #{connection['tenantId']}"
      end

      # Look for Demo Company first, fallback to first tenant
      demo_connection = connections.find do |c|
        c['tenantName']&.downcase&.include?("demo")
      end

      connection = demo_connection || connections.first

      Rails.logger.info "Selected tenant: #{connection['tenantName']} (#{connection['tenantId']})"

      # Store the credentials (in production, you'd store these securely per user)
      Rails.cache.write('xero_token_set', token_set, expires_in: 30.minutes)
      Rails.cache.write('xero_tenant_id', connection['tenantId'], expires_in: 30.minutes)
      Rails.cache.write('xero_tenant_name', connection['tenantName'], expires_in: 30.minutes)

      # Instead of syncing, let's just test a simple API call
      test_simple_api_call(xero_client, connection['tenantId'], token_set)

      redirect_to root_path, notice: "Successfully connected to Xero (#{connection['tenantName']})!"

    rescue => e
      Rails.logger.error "Xero OAuth error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
      redirect_to root_path, alert: "Failed to connect to Xero: #{e.message}"
    end
  end

  private

  def test_simple_api_call(xero_client, tenant_id, token_set)
    begin
      Rails.logger.info "=== DEBUGGING API CALL ==="
      Rails.logger.info "Tenant ID: #{tenant_id}"
      Rails.logger.info "Token keys: #{token_set.keys}"
      Rails.logger.info "Gem version: #{XeroRuby::VERSION rescue 'Unknown'}"

      # Set token
      xero_client.set_token_set(token_set)

      # Try to inspect what URL the gem is trying to hit
      accounting_api = XeroRuby::AccountingApi.new(xero_client)

      # Let's try the simplest possible call first - get organizations
      Rails.logger.info "Trying get_organisations..."
      begin
        orgs_response = accounting_api.get_organisations(tenant_id)
        Rails.logger.info "✅ get_organisations worked! Got #{orgs_response.organisations&.length || 0} orgs"

        # If that works, try contacts
        Rails.logger.info "Trying get_contacts..."
        contacts_response = accounting_api.get_contacts(tenant_id)
        Rails.logger.info "✅ get_contacts worked! Got #{contacts_response.contacts&.length || 0} contacts"

      rescue XeroRuby::ApiError => api_error
        Rails.logger.error "❌ API Error Details:"
        Rails.logger.error "  Code: #{api_error.code}"
        Rails.logger.error "  Message: #{api_error.message}"
        Rails.logger.error "  Headers: #{api_error.response_headers}" if api_error.respond_to?(:response_headers)
        Rails.logger.error "  Body: #{api_error.response_body}" if api_error.respond_to?(:response_body)

        # Let's also try to see what URL was being called
        if api_error.respond_to?(:response_headers) && api_error.response_headers
          Rails.logger.error "  Response headers suggest URL issues"
        end

        # Try a manual HTTP call to see what's happening
        test_manual_api_call(tenant_id, token_set)

        raise api_error
      end

    rescue => e
      Rails.logger.error "Unexpected error in test: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
      raise e
    end
  end

  def test_manual_api_call(tenant_id, token_set)
    begin
      require 'net/http'
      require 'uri'

      # Try calling the Xero API directly to see what happens
      uri = URI("https://api.xero.com/api.xro/2.0/Organisations")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{token_set['access_token']}"
      request['xero-tenant-id'] = tenant_id
      request['Accept'] = 'application/json'

      Rails.logger.info "=== MANUAL API CALL ==="
      Rails.logger.info "URL: #{uri}"
      Rails.logger.info "Headers: Authorization: Bearer [REDACTED], xero-tenant-id: #{tenant_id}"

      response = http.request(request)

      Rails.logger.info "Response Code: #{response.code}"
      Rails.logger.info "Response Headers: #{response.to_hash}"
      Rails.logger.info "Response Body: #{response.body[0..500]}..." # First 500 chars

    rescue => manual_error
      Rails.logger.error "Manual API call failed: #{manual_error.message}"
    end
  end
end
