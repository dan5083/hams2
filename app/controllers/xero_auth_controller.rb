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
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
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
      Rails.logger.info "Token set keys: #{token_set.keys}"

      # In xero-ruby v12.x, the method signature requires proper options hash
      # Try the most basic call first - no options parameter
      begin
        response = accounting_api.get_contacts(tenant_id)
        Rails.logger.info "Basic call successful"
      rescue => basic_error
        Rails.logger.error "Basic call failed: #{basic_error.message}"

        # Try with empty options hash
        begin
          response = accounting_api.get_contacts(tenant_id, {})
          Rails.logger.info "Call with empty options successful"
        rescue => empty_opts_error
          Rails.logger.error "Empty options call failed: #{empty_opts_error.message}"

          # Try with explicit options that might be expected
          opts = {
            where: nil,
            order: nil,
            ids: nil,
            page: nil,
            include_archived: nil,
            summary_only: nil,
            search_term: nil,
            if_modified_since: nil
          }
          response = accounting_api.get_contacts(tenant_id, **opts)
          Rails.logger.info "Call with explicit options successful"
        end
      end

      contacts = response.contacts

      Rails.logger.info "Found #{contacts.length} contacts"

      # Clear existing demo data and sync real data
      XeroContact.destroy_all
      Organization.destroy_all

      customer_count = 0
      contacts.each do |contact|
        # Only sync customers (not suppliers or employees)
        next unless contact.is_customer

        Rails.logger.info "Creating contact: #{contact.name}"

        # Handle potential nil values more defensively
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

      Rails.logger.info "Synced #{customer_count} customers successfully"

    rescue XeroRuby::ApiError => e
      Rails.logger.error "=== XERO API ERROR DETAILS ==="
      Rails.logger.error "Error message: #{e.message}"
      Rails.logger.error "HTTP status code: #{e.code}" if e.respond_to?(:code)
      Rails.logger.error "Response headers: #{e.response_headers}" if e.respond_to?(:response_headers)
      Rails.logger.error "Response body: '#{e.response_body}'" if e.respond_to?(:response_body)
      Rails.logger.error "=== END ERROR DETAILS ==="

      # Try a simple test to see if we can access anything
      begin
        Rails.logger.info "Trying to get organizations instead..."
        org_response = accounting_api.get_organisations(tenant_id)
        Rails.logger.info "Organizations call worked! Got #{org_response.organisations&.length || 0} orgs"

        # If orgs work but contacts don't, it might be a permissions issue
        if org_response.organisations&.any?
          org = org_response.organisations.first
          Rails.logger.info "First org: #{org.name}"
        end
      rescue => org_error
        Rails.logger.error "Organizations call also failed: #{org_error.message}"
      end

      raise e
    rescue => e
      Rails.logger.error "Unexpected error during Xero sync: #{e.class.name}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if e.backtrace
      raise e
    end
  end
end
