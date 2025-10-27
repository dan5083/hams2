# app/controllers/xero_auth_controller.rb
class XeroAuthController < ApplicationController
  before_action :require_xero_access, except: [:authorize, :callback]
  allow_unauthenticated_access only: [:authorize, :callback]

  def authorize
    Rails.logger.info "=== STARTING XERO AUTH ==="

    creds = {
      client_id: ENV['XERO_CLIENT_ID'],
      client_secret: ENV['XERO_CLIENT_SECRET'],
      redirect_uri: ENV['XERO_REDIRECT_URI'],
      scopes: 'accounting.contacts accounting.transactions offline_access'
    }

    xero_client = XeroRuby::ApiClient.new(credentials: creds)
    auth_url = xero_client.authorization_url
    redirect_to auth_url, allow_other_host: true
  end

  def callback
    Rails.logger.info "=== XERO CALLBACK RECEIVED ==="

    auth_code = params[:code]
    if auth_code.blank?
      redirect_to root_path, alert: "Xero authorization failed"
      return
    end

    begin
      creds = {
        client_id: ENV['XERO_CLIENT_ID'],
        client_secret: ENV['XERO_CLIENT_SECRET'],
        redirect_uri: ENV['XERO_REDIRECT_URI']
      }

      xero_client = XeroRuby::ApiClient.new(credentials: creds)
      token_set = xero_client.get_token_set_from_callback(params)

      if token_set.nil? || token_set.key?('error')
        redirect_to root_path, alert: "Failed to get valid token from Xero"
        return
      end

      xero_client.set_token_set(token_set)
      connections = xero_client.connections

      if connections.empty?
        redirect_to root_path, alert: "No Xero organizations found"
        return
      end

      # Store the token set first
      session[:xero_token_set] = token_set

      total_contacts = 0
      org_names = []

      # Process ALL connections, prioritizing Hard Anodising Surface Treatments
      connections.each do |connection|
        tenant_id = connection['tenantId']
        tenant_name = connection['tenantName']

        Rails.logger.info "Processing organization: #{tenant_name}"

        # Store the main organization (prioritize Hard Anodising)
        if tenant_name.downcase.include?('hard anodising') || session[:xero_tenant_id].nil?
          session[:xero_tenant_id] = tenant_id
          session[:xero_tenant_name] = tenant_name
          Rails.logger.info "Set primary organization: #{tenant_name}"
        end

        org_names << tenant_name

        # Sync contacts from this organization
        contact_count = sync_contacts_from_xero(token_set, tenant_id)
        total_contacts += contact_count

        Rails.logger.info "✅ Synced #{contact_count} contacts from #{tenant_name}"
      end

      if total_contacts > 0
        redirect_to root_path, notice: "✅ Connected to #{org_names.join(', ')} and synced #{total_contacts} total contacts!"
      else
        redirect_to root_path, alert: "Connected but no contacts were synced"
      end

    rescue => e
      Rails.logger.error "Xero OAuth error: #{e.message}"
      redirect_to root_path, alert: "Failed to connect to Xero: #{e.message}"
    end
  end

  def test_api
    Rails.logger.info "=== MANUAL API TEST ==="

    token_set = session[:xero_token_set]
    tenant_id = session[:xero_tenant_id]

    if token_set.nil? || tenant_id.nil?
      render plain: "❌ No token/tenant found. Connect via /auth/xero first."
      return
    end

    begin
      contacts_data = fetch_contacts_from_xero(token_set, tenant_id)
      customers = contacts_data.select { |c| c['IsCustomer'] == true }

      render plain: "✅ SUCCESS! API call worked.\nTotal contacts: #{contacts_data.length}\nCustomers: #{customers.length}\n\nFirst few customers:\n#{customers.first(3).map { |c| "- #{c['Name']}" }.join("\n")}"

    rescue => e
      Rails.logger.error "API test error: #{e.message}"
      render plain: "❌ API test failed: #{e.message}"
    end
  end

  private

  def sync_contacts_from_xero(token_set, tenant_id)
    begin
      Rails.logger.info "Fetching contacts from Xero..."

      contacts_data = fetch_contacts_from_xero(token_set, tenant_id)
      Rails.logger.info "Found #{contacts_data.length} total contacts"

      customers = contacts_data.select { |c| c['IsCustomer'] == true }
      suppliers = contacts_data.select { |c| c['IsSupplier'] == true }

      Rails.logger.info "Customers: #{customers.length}, Suppliers: #{suppliers.length}"

      contact_count = 0
      contacts_data.each do |contact|
        # Skip archived contacts
        next if contact['ContactStatus'] == 'ARCHIVED'

        # Find or create XeroContact record
        xero_contact = XeroContact.find_or_initialize_by(xero_id: contact['ContactID'])
        xero_contact.assign_attributes(
          name: contact['Name'] || 'Unknown',
          contact_status: contact['ContactStatus'] || 'ACTIVE',
          is_customer: contact['IsCustomer'] || false,
          is_supplier: contact['IsSupplier'] || false,
          accounts_receivable_tax_type: contact['AccountsReceivableTaxType'],
          accounts_payable_tax_type: contact['AccountsPayableTaxType'],
          xero_data: contact,
          last_synced_at: Time.current
        )
        xero_contact.save!

        # Find or create organization
        organization = Organization.find_or_initialize_by(xero_contact: xero_contact)

        if organization.new_record?
          organization.assign_attributes(
            name: contact['Name'] || 'Unknown',
            enabled: true,
            is_customer: contact['IsCustomer'] || false,
            is_supplier: contact['IsSupplier'] || false
          )
        else
          # Update organization details from fresh Xero data
          organization.assign_attributes(
            name: contact['Name'] || organization.name,
            is_customer: contact['IsCustomer'] || false,
            is_supplier: contact['IsSupplier'] || false
          )
        end

        organization.save!

        # Sync address for customer organizations
        if organization.is_customer
          begin
            organization.sync_address_from_xero!
          rescue => e
            Rails.logger.error "Failed to sync address for #{organization.name}: #{e.message}"
          end
        end

        contact_count += 1
      end

      Rails.logger.info "✅ Successfully synced #{contact_count} contacts"
      contact_count

    rescue => e
      Rails.logger.error "Sync error: #{e.message}"
      0
    end
  end

  def fetch_contacts_from_xero(token_set, tenant_id)
    require 'net/http'
    require 'uri'
    require 'json'

    uri = URI("https://api.xero.com/api.xro/2.0/Contacts?includeArchived=false")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{token_set['access_token']}"
    request['xero-tenant-id'] = tenant_id
    request['Accept'] = 'application/json'

    response = http.request(request)

    if response.code == '200'
      data = JSON.parse(response.body)
      return data['Contacts'] || []
    else
      raise "API call failed with status #{response.code}: #{response.body}"
    end
  end
end
