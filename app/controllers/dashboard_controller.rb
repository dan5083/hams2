# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  before_action :set_no_cache_headers
  def index
    # DEBUG: Log session information
    Rails.logger.info "=== XERO CONNECTION DEBUG ==="
    Rails.logger.info "Session keys: #{session.keys}"
    Rails.logger.info "Token set present: #{session[:xero_token_set].present?}"
    Rails.logger.info "Token set class: #{session[:xero_token_set].class}" if session[:xero_token_set]
    Rails.logger.info "Tenant ID present: #{session[:xero_tenant_id].present?}"
    Rails.logger.info "Tenant ID value: #{session[:xero_tenant_id]}" if session[:xero_tenant_id]
    Rails.logger.info "Tenant name: #{session[:xero_tenant_name]}" if session[:xero_tenant_name]

    # Load pending invoices for Xero sync
    @pending_invoices = Invoice.requiring_xero_sync
                              .includes(:customer)
                              .order(created_at: :desc)

    # Check Xero connection status
    @xero_connected = xero_connected?
    Rails.logger.info "Xero connected result: #{@xero_connected}"
    @xero_tenant_name = session[:xero_tenant_name]

    # Load other dashboard data as needed
    # @recent_works_orders = WorksOrder.recent.limit(5)
    # @recent_release_notes = ReleaseNote.recent.limit(5)
  end

  private

  def set_no_cache_headers
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
  end

  def xero_connected?
    token_present = session[:xero_token_set].present?
    tenant_present = session[:xero_tenant_id].present?

    Rails.logger.info "Token present: #{token_present}, Tenant present: #{tenant_present}"

    result = token_present && tenant_present
    Rails.logger.info "Final xero_connected result: #{result}"

    result
  end
end
