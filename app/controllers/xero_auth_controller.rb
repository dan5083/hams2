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

      # Sync customers from Xero
      tenant_id = connection['tenantId']
      sync_customers_from_xero(xero_client, tenant_id, token_set)

      redirect_to root_path, notice: "Successfully connected to Xero (#{connection['tenantName']}) and synced #{Organization.count} customers!"

    rescue => e
      Rails.logger.error "Xero OAuth error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
      redirect_to root_path, alert: "Failed to connect to Xero: #{e.message}"
    end
  end

  private

  def sync_customers_from_xero(xero_client, tenant_id, token_set)
    begin
      Rails.logger.info "Starting sync with tenant: #{tenant_id}"

      # CRITICAL: Ensure token is set and refresh if needed
      xero_client.set_token_set(token_set)

      # Check if token needs refreshing (based on official sample)
      if token_expired?(token_set)
        Rails.logger.info "Token expired, refreshing..."
        token_set = xero_client.refresh_token_set(token_set)
        xero_client.set_token_set(token_set)
        # Update cache with new token
        Rails.cache.write('xero_token_set', token_set, expires_in: 30.minutes)
      end

      # Create accounting API instance
      accounting_api = XeroRuby::AccountingApi.new(xero_client)

      Rails.logger.info "Making API call to get contacts..."

      # Make the API call - using the pattern from the official sample
      response = accounting_api.get_contacts(tenant_id)

      contacts = response.contacts
      Rails.logger.info "Successfully retrieved #{contacts.length} contacts"

      # Clear existing data and sync
      XeroContact.destroy_all
      Organization.destroy_all

      customer_count = 0
      contacts.each do |contact|
        # Only sync customers
        next unless contact.is_customer

        Rails.logger.info "Creating contact: #{contact.name}"

        # Create XeroContact record
        xero_contact = XeroContact.create!(
          name: contact.name || 'Unknown',
          contact_status: contact.contact_status&.to_s || 'ACTIVE',
          is_customer: contact.is_customer || false,
          is_supplier: contact.is_supplier || false,
          accounts_receivable_tax_type: contact.accounts_receivable_tax_type,
          accounts_payable_tax_type: contact.accounts_payable_tax_type,
          xero_id: contact.contact_id,
          xero_data: contact.to_hash,
          last_synced_at: Time.current
        )

        # Create corresponding organization
        Organization.create!(
          name: contact.name || 'Unknown',
          enabled: true,
          is_customer: contact.is_customer || false,
          is_supplier: contact.is_supplier || false,
          xero_contact: xero_contact
        )

        customer_count += 1
      end

      Rails.logger.info "Successfully synced #{customer_count} customers"

    rescue XeroRuby::ApiError => e
      Rails.logger.error "=== XERO API ERROR ==="
      Rails.logger.error "Message: #{e.message}"
      Rails.logger.error "Code: #{e.code}" if e.respond_to?(:code)
      Rails.logger.error "Headers: #{e.response_headers}" if e.respond_to?(:response_headers)
      Rails.logger.error "Body: #{e.response_body}" if e.respond_to?(:response_body)

      # Check if it's a token issue
      if e.code == 401
        Rails.logger.error "Authentication failed - token may be invalid"
      elsif e.code == 404
        Rails.logger.error "API endpoint not found - check tenant ID and API version"
      end

      raise e
    rescue => e
      Rails.logger.error "Unexpected error: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
      raise e
    end
  end

  # Helper method to check if token is expired (from official sample)
  def token_expired?(token_set)
    return true unless token_set['access_token']

    # Decode the JWT token to check expiration
    begin
      require 'jwt'
      decoded_token = JWT.decode(token_set['access_token'], nil, false)
      exp = decoded_token[0]['exp']
      return Time.at(exp) <= Time.now
    rescue
      # If we can't decode, assume it's expired
      return true
    end
  end
end
