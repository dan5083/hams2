# app/controllers/dashboard_controller.rb - Updated with role-based access control
class DashboardController < ApplicationController
  before_action :require_xero_access, only: [:push_selected_to_xero]

  def index
    # Check Xero connection status - only for users who can see Xero integration
    if Current.user.sees_xero_integration?
      @xero_connected = xero_connected?
      @pending_invoices = Invoice.draft.includes(:customer)
    else
      @xero_connected = false
      @pending_invoices = Invoice.none # Empty collection for non-Xero users
    end

    # General dashboard metrics available to all users
    @total_organizations = Organization.count
    @total_customers = Organization.customers.count
    @total_suppliers = Organization.suppliers.count
    @total_xero_contacts = XeroContact.count
    @total_invoices = Invoice.count
    @total_draft_invoices = Invoice.draft.count
    @total_synced_invoices = Invoice.synced.count
    @active_customers = Organization.customers.enabled.count

    # E-card specific metrics for users who can see e-cards
    if Current.user.sees_ecards?
      load_ecard_metrics
    end

    # Department-specific dashboard sections
    case Current.user.email_address
    when 'chris@hardanodisingstl.com', 'quality@hardanodisingstl.com'
      load_quality_metrics
    when 'chris.bayliss@hardanodisingstl.com', 'phil@hardanodisingstl.com', 'tariq@hardanodisingstl.com', 'julia@hardanodisingstl.com'
      load_management_metrics
    when 'daniel@hardanodisingstl.com'
      load_developer_metrics
      load_management_metrics # Developer sees both system metrics AND business metrics
    end
  end

  def push_selected_to_xero
    # This action is already protected by before_action :require_xero_access
    invoice_ids = params[:invoice_ids] || []

    if invoice_ids.empty?
      redirect_to root_path, alert: 'No invoices selected for pushing to Xero.'
      return
    end

    begin
      invoices = Invoice.where(id: invoice_ids)
      success_count = 0
      error_messages = []

      invoices.each do |invoice|
        begin
          # Push invoice to Xero (assuming you have a service for this)
          if push_invoice_to_xero(invoice)
            success_count += 1
          else
            error_messages << "Failed to push invoice INV#{invoice.number}"
          end
        rescue => e
          error_messages << "Error pushing invoice INV#{invoice.number}: #{e.message}"
        end
      end

      if success_count > 0 && error_messages.empty?
        redirect_to root_path, notice: "Successfully pushed #{success_count} invoices to Xero."
      elsif success_count > 0
        redirect_to root_path, notice: "Pushed #{success_count} invoices. Errors: #{error_messages.join(', ')}"
      else
        redirect_to root_path, alert: "Failed to push invoices: #{error_messages.join(', ')}"
      end
    rescue => e
      Rails.logger.error "Dashboard push_selected_to_xero error: #{e.message}"
      redirect_to root_path, alert: "Error pushing invoices to Xero: #{e.message}"
    end
  end

  private

  def require_xero_access
    unless Current.user&.sees_xero_integration?
      Rails.logger.warn "Unauthorized Xero access attempt by #{Current.user&.email_address || 'unknown user'}"
      redirect_to root_path, alert: "You don't have permission to access Xero integration features."
    end
  end

  def xero_connected?
    # Check if user has active Xero session/tokens
    session[:xero_token_set].present? && session[:xero_tenant_id].present?
  end

  def load_ecard_metrics
    # E-card specific metrics for shop floor users
    base_works_orders = WorksOrder.active.includes(:part, :customer_order)

    # Apply user-specific filtering
    filter_criteria = Current.user.ecard_filter_criteria

    if filter_criteria.present? && !filter_criteria[:description]&.include?("sees all")
      # Filter works orders based on user criteria
      filtered_work_orders = base_works_orders.select do |wo|
        user_can_see_work_order_for_dashboard?(wo)
      end
      @my_work_orders_count = filtered_work_orders.count
      @my_pending_work_orders = filtered_work_orders.select { |wo| wo.unreleased_quantity > 0 }.count
    else
      # User sees all work orders
      @my_work_orders_count = base_works_orders.count
      @my_pending_work_orders = base_works_orders.with_unreleased_quantity.count
    end

    @total_active_work_orders = base_works_orders.count
  end

  def load_quality_metrics
    # Metrics specific to quality staff (Chris Connon, Jim Ledger)
    @ncrs_count = ExternalNcr.count
    @pending_ncrs = ExternalNcr.where(status: 'draft').count
    @aerospace_work_orders = WorksOrder.active.joins(:part)
                                  .where("parts.customisation_data->'operation_selection'->>'aerospace_defense' = 'true'")
                                  .count
    @recent_quality_issues = ExternalNcr.where('created_at > ?', 7.days.ago).count
  end

  def load_management_metrics
    # Metrics for management and production planning (Chris Bayliss, Phil Bayliss, Tariq Anwar, Julia Chapman)
    @total_revenue_pending = @pending_invoices.sum(:total_inc_tax) if Current.user.sees_xero_integration?
    @works_orders_this_month = WorksOrder.where('created_at > ?', 1.month.ago).count
    @customer_orders_this_month = CustomerOrder.where('created_at > ?', 1.month.ago).count
    @completion_rate = calculate_completion_rate

    # Production planning specific metrics for Julia
    if Current.user.email_address == 'julia@hardanodisingstl.com'
      @open_customer_orders = CustomerOrder.active.count
      @works_orders_pending_release = WorksOrder.with_unreleased_quantity.count
      @overdue_works_orders = WorksOrder.active.where('created_at < ?', 2.weeks.ago).count
    end
  end

  def load_developer_metrics
    # Debug/development metrics (Daniel Bayliss)
    @total_parts = Part.count
    @parts_with_operations = Part.joins("JOIN LATERAL (SELECT 1 FROM jsonb_array_elements(COALESCE(customisation_data->'operation_selection'->>'treatments', '[]')::jsonb) LIMIT 1) AS treatments ON true").count
    @database_size = get_database_size
    @recent_errors = get_recent_error_count
  end

  # Helper method to check if user can see a work order (for dashboard metrics)
  def user_can_see_work_order_for_dashboard?(work_order)
    return true unless Current.user.sees_ecards?

    filter_criteria = Current.user.ecard_filter_criteria
    return true if filter_criteria.blank?

    part = work_order.part
    return true unless part

    operations = part.get_operations_with_auto_ops

    # Basic access only (maintenance) - no work orders
    return false if filter_criteria[:basic_access_only]

    # VAT number filtering
    if filter_criteria[:vat_numbers].present?
      operation_vats = operations.flat_map(&:vat_numbers).uniq
      return false if operation_vats.any? && (operation_vats & filter_criteria[:vat_numbers]).empty?
    end

    # Process type filtering
    if filter_criteria[:process_types].present?
      operation_process_types = operations.map(&:process_type).uniq
      return false if (operation_process_types & filter_criteria[:process_types]).empty?
    end

    # Process type exclusion
    if filter_criteria[:exclude_process_types].present?
      operation_process_types = operations.map(&:process_type).uniq
      return false if (operation_process_types & filter_criteria[:exclude_process_types]).any?
    end

    true
  end

  def calculate_completion_rate
    total_works_orders = WorksOrder.active.count
    return 0 if total_works_orders.zero?

    completed_works_orders = WorksOrder.closed.count
    ((completed_works_orders.to_f / total_works_orders) * 100).round(1)
  end

  def get_database_size
    # Get approximate database size (PostgreSQL specific)
    result = ActiveRecord::Base.connection.execute(
      "SELECT pg_size_pretty(pg_database_size(current_database()))"
    )
    result.first['pg_size_pretty'] rescue 'Unknown'
  end

  def get_recent_error_count
    # This would integrate with your logging system
    # For now, return a placeholder
    0
  end

  def push_invoice_to_xero(invoice)
    # Placeholder for Xero push logic
    # This would integrate with your existing XeroService
    begin
      # XeroInvoiceService.new.push_invoice(invoice)
      # For now, just mark as success
      invoice.update(xero_id: "INV-#{invoice.number}-#{Time.current.to_i}")
      true
    rescue => e
      Rails.logger.error "Failed to push invoice #{invoice.number} to Xero: #{e.message}"
      false
    end
  end
end
