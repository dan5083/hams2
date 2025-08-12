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
    Rails.logger.info "Session ID: #{session.id}" if session.respond_to?(:id)

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

      Rails.logger.info "Creating Xero client..."
      xero_client = XeroRuby::ApiClient.new(credentials: creds)

      Rails.logger.info "Getting token set from callback..."
      token_set = xero_client.get_token_set_from_callback(params)

      Rails.logger.info "=== TOKEN SET ANALYSIS ==="
      if token_set
        Rails.logger.info "Token keys: #{token_set.keys}"
        Rails.logger.info "Has access_token?: #{token_set.key?('access_token')}"

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
      Rails.logger.info "Connections length: #{connections.length}" if connections.respond_to?(:length)

      if connections.empty?
        Rails.logger.error "❌ No connections found"
        redirect_to root_path, alert: "No Xero organizations found"
        return
      end

      connection = connections.first
      tenant_id = connection['tenantId']
      tenant_name = connection['tenantName']

      Rails.logger.info "=== STORING DATA ==="
      Rails.logger.info "Tenant ID: #{tenant_id}"
      Rails.logger.info "Tenant Name: #{tenant_name}"

      # Store in BOTH cache AND session for reliability
      Rails.cache.write('xero_token_set', token_set, expires_in: 1.hour)
      Rails.cache.write('xero_tenant_id', tenant_id, expires_in: 1.hour)
      Rails.cache.write('xero_tenant_name', tenant_name, expires_in: 1.hour)

      # Also store in session as backup
      session[:xero_token_set] = token_set
      session[:xero_tenant_id] = tenant_id
      session[:xero_tenant_name] = tenant_name

      Rails.logger.info "✅ Data stored in both cache and session"

      # Test immediately if we can read it back
      test_token = Rails.cache.read('xero_token_set')
      test_tenant = Rails.cache.read('xero_tenant_id')
      Rails.logger.info "Immediate read test - Token: #{test_token ? 'Found' : 'NOT FOUND'}, Tenant: #{test_tenant}"

      redirect_to root_path, notice: "✅ Connected to #{tenant_name}! Try /test_xero_api"

    rescue => e
      Rails.logger.error "=== CALLBACK ERROR ==="
      Rails.logger.error "Error: #{e.class}: #{e.message}"
      e.backtrace&.first(5)&.each { |line| Rails.logger.error "  #{line}" }

      redirect_to root_path, alert: "Failed to connect to Xero: #{e.message}"
    end
  end

  def test_api
    Rails.logger.info "=== MANUAL API TEST START ==="
    Rails.logger.info "Session ID: #{session.id}" if session.respond_to?(:id)

    # Try cache first, then session
    token_set = Rails.cache.read('xero_token_set')
    tenant_id = Rails.cache.read('xero_tenant_id')

    Rails.logger.info "From cache - Token: #{token_set ? 'Found' : 'Not found'}, Tenant: #{tenant_id}"

    # If cache is empty, try session
    if token_set.nil? || tenant_id.nil?
      Rails.logger.info "Cache empty, trying session..."
      token_set = session[:xero_token_set]
      tenant_id = session[:xero_tenant_id]
      Rails.logger.info "From session - Token: #{token_set ? 'Found' : 'Not found'}, Tenant: #{tenant_id}"
    end

    # If still nothing, show what we have
    if token_set.nil? || tenant_id.nil?
      Rails.logger.error "=== DEBUGGING STORAGE ==="
      Rails.logger.error "Cache keys: #{Rails.cache.instance_variable_get(:@data)&.keys rescue 'Cannot read cache'}"
      Rails.logger.error "Session keys: #{session.keys}"
      Rails.logger.error "Session data: #{session.to_hash}"

      render plain: "❌ No cached token/tenant found.\nCache: Token=#{token_set ? 'Found' : 'Missing'}, Tenant=#{tenant_id ? 'Found' : 'Missing'}\nSession: Token=#{session[:xero_token_set] ? 'Found' : 'Missing'}, Tenant=#{session[:xero_tenant_id] ? 'Found' : 'Missing'}\nConnect via /auth/xero first."
      return
    end

    Rails.logger.info "Found data! Testing API..."
    Rails.logger.info "Token keys: #{token_set.keys}"
    Rails.logger.info "Access token: #{token_set['access_token']&.first(30)}..."

    begin
      require 'net/http'
      require 'uri'

      uri = URI("https://api.xero.com/api.xro/2.0/Contacts")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{token_set['access_token']}"
      request['xero-tenant-id'] = tenant_id
      request['Accept'] = 'application/json'

      Rails.logger.info "Making request to: #{uri}"
      Rails.logger.info "Headers: Authorization: Bearer [REDACTED], xero-tenant-id: #{tenant_id}"

      response = http.request(request)

      Rails.logger.info "=== API RESPONSE ==="
      Rails.logger.info "Status: #{response.code} #{response.message}"
      Rails.logger.info "Body length: #{response.body&.length}"
      Rails.logger.info "Body preview: #{response.body&.first(200)}..."

      if response.code == '200'
        # Parse JSON to count contacts
        begin
          data = JSON.parse(response.body)
          contacts = data['Contacts'] || []
          customers = contacts.select { |c| c['IsCustomer'] == true }

          Rails.logger.info "Total contacts: #{contacts.length}, Customers: #{customers.length}"

          render plain: "✅ SUCCESS! API call worked.\nTotal contacts: #{contacts.length}\nCustomers: #{customers.length}\n\nFirst few customers:\n#{customers.first(3).map { |c| "- #{c['Name']}" }.join("\n")}"
        rescue JSON::ParserError => e
          render plain: "✅ API call succeeded but JSON parse failed: #{e.message}\n\nRaw response: #{response.body[0..500]}"
        end
      else
        render plain: "❌ API call failed with #{response.code}.\nResponse: #{response.body}\nCheck logs for details."
      end

    rescue => e
      Rails.logger.error "Manual HTTP error: #{e.message}"
      render plain: "❌ Manual API test failed: #{e.message}. Check logs."
    end
  end
end
