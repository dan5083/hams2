# app/controllers/dashboard_controller.rb
class DashboardController < ApplicationController
  def index
    # Load pending invoices for Xero sync
    @pending_invoices = Invoice.requiring_xero_sync
                              .includes(:customer)
                              .order(created_at: :desc)

    # Check Xero connection status
    @xero_connected = xero_connected?
    @xero_tenant_name = session[:xero_tenant_name]

    # Load other dashboard data as needed
    # @recent_works_orders = WorksOrder.recent.limit(5)
    # @recent_release_notes = ReleaseNote.recent.limit(5)
  end

  private

  def xero_connected?
    session[:xero_token_set].present? && session[:xero_tenant_id].present?
  end
end
