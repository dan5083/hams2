class XeroAuthController < ApplicationController
  def authorize
    Rails.logger.info "=== STARTING XERO AUTH ==="
    Rails.logger.info "CLIENT_ID: #{ENV['XERO_CLIENT_ID']&.first(8)}..."
    Rails.logger.info "REDIRECT_URI: #{ENV['XERO_REDIRECT_URI']}"

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
    Rails.logger.info "Auth URL: #{auth_url}"
    redirect_to auth_url, allow_other_host: true
  end

  def callback
    Rails.logger.info "=== XERO CALLBACK RECEIVED ==="
    Rails.logger.info "Raw params: #{params.inspect}"
    Rails.logger.info "Request method: #{request.method}"
    Rails.logger.info "Request headers: #{request.headers.to_h.select { |k,v| k.start_with?('HTTP_') }}"

    auth_code = params[:code]
    Rails.logger.info "Auth code: #{auth_code&.first(20)}..." if auth_code

    if auth_code.blank?
      Rails.logger.error "❌ No auth code received"
      redirect_to root_path, alert: "Xero authorization failed - no code"
      return
    end

    begin
      creds = {
        client_id: ENV['XERO_CLIENT_ID'],
        client_secret: ENV['XERO_CLIENT_SECRET'],
        redirect_uri: ENV['XERO_REDIRECT_URI']
      }

      Rails.logger.info "Creating Xero client with:"
      Rails.logger.info "  client_id: #{creds[:client_id]&.first(8)}..."
      Rails.logger.info "  redirect_uri: #{creds[:redirect_uri]}"

      xero_client = XeroRuby::ApiClient.new(credentials: creds)

      Rails.logger.info "Getting token set from callback..."
      token_set = xero_client.get_token_set_from_callback(params)

      Rails.logger.info "=== TOKEN SET ANALYSIS ==="
      Rails.logger.info "Token set class: #{token_set.class}"
      Rails.logger.info "Token set nil?: #{token_set.nil?}"

      if token_set
        Rails.logger.info "Token keys: #{token_set.keys}"
        Rails.logger.info "Has access_token?: #{token_set.key?('access_token')}"
        Rails.logger.info "Has error?: #{token_set.key?('error')}"

        if token_set.key?('access_token')
          Rails.logger.info "Access token starts: #{token_set['access_token']&.first(20)}..."
        end

        if token_set.key?('error')
          Rails.logger.error "❌ Token error: #{token_set['error']}"
          redirect_to root_path, alert: "Token error: #{token_set['error']}"
          return
        end
      else
        Rails.logger.error "❌ Token set is nil!"
        redirect_to root_path, alert: "Failed to get token from Xero"
        return
      end

      Rails.logger.info "Setting token set on client..."
      xero_client.set_token_set(token_set)

      Rails.logger.info "Getting connections..."
      connections = xero_client.connections

      Rails.logger.info "=== CONNECTIONS ANALYSIS ==="
      Rails.logger.info "Connections class: #{connections.class}"
      Rails.logger.info "Connections length: #{connections.length}" if connections.respond_to?(:length)

      if connections.is_a?(Array)
        connections.each_with_index do |conn, i|
          Rails.logger.info "Connection #{i}: #{conn.inspect}"
        end
      else
        Rails.logger.info "Connections content: #{connections.inspect}"
      end

      if connections.is_a?(Hash) && connections.key?('error')
        Rails.logger.error "❌ Connections error: #{connections}"
        redirect_to root_path, alert: "Failed to get organizations: #{connections['error']}"
        return
      end

      if connections.empty?
        Rails.logger.error "❌ No connections found"
        redirect_to root_path, alert: "No Xero organizations found"
        return
      end

      connection = connections.first
      Rails.logger.info "=== SELECTED CONNECTION ==="
      Rails.logger.info "Connection keys: #{connection.keys}" if connection.respond_to?(:keys)
      Rails.logger.info "Tenant ID: #{connection['tenantId']}" if connection.is_a?(Hash)
      Rails.logger.info "Tenant Name: #{connection['tenantName']}" if connection.is_a?(Hash)

      # Cache the important data
      Rails.cache.write('xero_token_set', token_set, expires_in: 30.minutes)
      Rails.cache.write('xero_tenant_id', connection['tenantId'], expires_in: 30.minutes)
      Rails.cache.write('xero_tenant_name', connection['tenantName'], expires_in: 30.minutes)

      Rails.logger.info "✅ Data cached successfully"

      # DON'T try API calls yet - just succeed
      redirect_to root_path, notice: "✅ Connected to #{connection['tenantName']}! Now try /test_xero_api to test API calls."

    rescue => e
      Rails.logger.error "=== CALLBACK ERROR ==="
      Rails.logger.error "Error class: #{e.class}"
      Rails.logger.error "Error message: #{e.message}"
      Rails.logger.error "Backtrace:"
      e.backtrace&.first(10)&.each { |line| Rails.logger.error "  #{line}" }

      redirect_to root_path, alert: "Failed to connect to Xero: #{e.message}"
    end
  end

  def test_api
    Rails.logger.info "=== MANUAL API TEST ==="

    token_set = Rails.cache.read('xero_token_set')
    tenant_id = Rails.cache.read('xero_tenant_id')

    Rails.logger.info "Token from cache: #{token_set ? 'Found' : 'Not found'}"
    Rails.logger.info "Tenant from cache: #{tenant_id}"

    if token_set.nil? || tenant_id.nil?
      render plain: "❌ No cached token/tenant. Connect to Xero first via /auth/xero"
      return
    end

    Rails.logger.info "Token keys: #{token_set.keys}"
    Rails.logger.info "Access token: #{token_set['access_token']&.first(30)}..."

    begin
      require 'net/http'
      require 'uri'

      uri = URI("https://api.xero.com/api.xro/2.0/Organisations")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{token_set['access_token']}"
      request['xero-tenant-id'] = tenant_id
      request['Accept'] = 'application/json'

      Rails.logger.info "Making request to: #{uri}"
      Rails.logger.info "Headers: Authorization: Bearer [REDACTED], xero-tenant-id: #{tenant_id}"

      response = http.request(request)

      Rails.logger.info "=== MANUAL HTTP RESPONSE ==="
      Rails.logger.info "Status: #{response.code} #{response.message}"
      Rails.logger.info "Headers: #{response.to_hash}"
      Rails.logger.info "Body length: #{response.body&.length}"
      Rails.logger.info "Body: #{response.body}"

      if response.code == '200'
        render plain: "✅ SUCCESS! API call worked. Response: #{response.body[0..500]}"
      else
        render plain: "❌ API call failed with #{response.code}. Check logs for details."
      end

    rescue => e
      Rails.logger.error "Manual HTTP error: #{e.message}"
      render plain: "❌ Manual API test failed: #{e.message}. Check logs."
    end
  end
end
