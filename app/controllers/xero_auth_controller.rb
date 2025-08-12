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

      # Get available tenants (companies)
      tenants = xero_client.connections

      if tenants.empty?
        redirect_to root_path, alert: "No Xero organizations found"
        return
      end

      # Log all available tenants
      Rails.logger.info "Available Xero tenants:"
      tenants.each do |t|
        Rails.logger.info "- Name: '#{t['tenantName']}', ID: #{t['tenantId']}"
      end

      # Look for Demo Company first, fallback to first tenant
      demo_tenant = tenants.find do |t|
        t['tenantName']&.downcase&.include?("demo")
      end

      tenant = demo_tenant || tenants.first

      Rails.logger.info "Selected tenant: #{tenant['tenantName']} (#{tenant['tenantId']})"

      # Store the credentials (in production, you'd store these securely per user)
      Rails.cache.write('xero_token_set', token_set, expires_in: 30.minutes)
      Rails.cache.write('xero_tenant_id', tenant['tenantId'], expires_in: 30.minutes)
      Rails.cache.write('xero_tenant_name', tenant['tenantName'], expires_in: 30.minutes)

      # Sync customers from Xero
      sync_customers_from_xero(xero_client, tenant['tenantId'], token_set)

      redirect_to root_path, notice: "Successfully connected to Xero (#{tenant['tenantName']}) and synced #{Organization.count} customers!"

    rescue => e
      Rails.logger.error "Xero OAuth error: #{e.message}"
      redirect_to root_path, alert: "Failed to connect to Xero: #{e.message}"
    end
  end

  private

  def sync_customers_from_xero(xero_client, tenant_id, token_set)
    # Set the token set on the client first
    xero_client.set_token_set(token_set)

    # Use the authenticated client to get real contacts
    accounting_api = XeroRuby::AccountingApi.new(xero_client)

    begin
      Rails.logger.info "Fetching contacts from tenant: #{tenant_id}"
      response = accounting_api.get_contacts(tenant_id)
      contacts = response.contacts

      Rails.logger.info "Found #{contacts.length} contacts"

      # Clear existing demo data and sync real data
      XeroContact.destroy_all
      Organization.destroy_all

      contacts.each do |contact|
        # Only sync customers (not suppliers or employees)
        next unless contact.is_customer

        Rails.logger.info "Creating contact: #{contact.name}"

        xero_contact = XeroContact.create!(
          name: contact.name,
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
          name: contact.name,
          enabled: true,
          is_customer: contact.is_customer || false,
          is_supplier: contact.is_supplier || false,
          xero_contact: xero_contact
        )
      end

      Rails.logger.info "Synced #{Organization.count} customers successfully"

    rescue XeroRuby::ApiError => e
      Rails.logger.error "Xero API Error: #{e.message}"
      Rails.logger.error "Response code: #{e.code}" if e.respond_to?(:code)
      Rails.logger.error "Response headers: #{e.response_headers}" if e.respond_to?(:response_headers)
      Rails.logger.error "Response body: #{e.response_body}" if e.respond_to?(:response_body)
      raise e
    end
  end
end
