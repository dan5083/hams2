class XeroAuthController < ApplicationController
  def authorize
    # Initialize Xero client for OAuth
    creds = {
      client_id: ENV['XERO_CLIENT_ID'] || Rails.application.credentials.dig(:xero, :client_id),
      client_secret: ENV['XERO_CLIENT_SECRET'] || Rails.application.credentials.dig(:xero, :client_secret),
      redirect_uri: ENV['XERO_REDIRECT_URI'] || Rails.application.credentials.dig(:xero, :redirect_uri),
      scopes: 'accounting.contacts accounting.transactions'
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
      token_set = xero_client.get_token_set_from_callback(auth_code)

      # Get available tenants (companies)
      tenants = xero_client.connections

      if tenants.empty?
        redirect_to root_path, alert: "No Xero organizations found"
        return
      end

      # For now, use the first tenant (demo company)
      tenant = tenants.first

      # Store the credentials (in production, you'd store these securely per user)
      Rails.cache.write('xero_token_set', token_set, expires_in: 30.minutes)
      Rails.cache.write('xero_tenant_id', tenant.tenant_id, expires_in: 30.minutes)

      # Sync customers from Xero
      sync_customers_from_xero(xero_client, tenant.tenant_id)

      redirect_to root_path, notice: "Successfully connected to Xero and synced #{Organization.count} customers!"

    rescue => e
      Rails.logger.error "Xero OAuth error: #{e.message}"
      redirect_to root_path, alert: "Failed to connect to Xero: #{e.message}"
    end
  end

  private

  def sync_customers_from_xero(xero_client, tenant_id)
    # Use the authenticated client to get real contacts
    accounting_api = XeroRuby::AccountingApi.new(xero_client)

    begin
      response = accounting_api.get_contacts(tenant_id)
      contacts = response.contacts

      # Clear existing demo data and sync real data
      XeroContact.destroy_all
      Organization.destroy_all

      contacts.each do |contact|
        # Only sync customers (not suppliers or employees)
        next unless contact.is_customer

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

    rescue XeroRuby::ApiError => e
      Rails.logger.error "Xero API Error: #{e.message}"
      raise e
    end
  end
end
