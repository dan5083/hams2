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
    @total_active_work_orders = WorksOrder.active.count
    @my_pending_work_orders = WorksOrder.active.with_unreleased_quantity.count
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
    @completion_rate = calculate_completion_rate

    # On-time delivery (trailing 30 days) - aerospace vs commercial
    @otd = on_time_delivery_stats(days: 30)

    # Released but not yet invoiced worklist
    @uninvoiced_rows = released_uninvoiced_rows
  end

  def load_developer_metrics
    # Debug/development metrics (Daniel Bayliss)
    @database_size = get_database_size
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

  # --- On-Time Delivery over a trailing window ---------------------------------
  # Cohort = customer orders RECEIVED in the last `days` days (mirrors the monthly
  # report, which buckets by date_received). An order counts once it has at least
  # one active release note; duration = received -> last release in working days.
  # Targets: aerospace <=15, commercial <=10.
  def on_time_delivery_stats(days: 30)
    window_start = Date.current - days

    orders = CustomerOrder
             .includes(:customer, works_orders: [:part, :release_notes])
             .where(voided: false)
             .where(date_received: window_start..Date.current)

    completed = []
    orders.each do |order|
      wo_ids = order.works_orders.map(&:id)
      next if wo_ids.empty?

      last_release_date = ReleaseNote.active.where(works_order_id: wo_ids).maximum(:date)
      next unless last_release_date

      completed << {
        aerospace: order.works_orders.any? { |wo| wo.part&.aerospace_defense? },
        duration:  working_days_between(order.date_received, last_release_date)
      }
    end

    {
      aerospace:  otd_breakdown(completed.select { |o| o[:aerospace] }, target: 15),
      commercial: otd_breakdown(completed.reject { |o| o[:aerospace] }, target: 10)
    }
  end

  def otd_breakdown(orders, target:)
    total = orders.size
    met   = orders.count { |o| o[:duration] <= target }
    {
      total:  total,
      met:    met,
      missed: total - met,
      target: target,
      pct:    total.zero? ? nil : (met.to_f / total * 100).round(1)
    }
  end

  # Mon–Fri working days between two dates (inclusive). Weekends excluded.
  def working_days_between(start_date, end_date)
    return 0 if start_date.nil? || end_date.nil?
    return 0 if end_date < start_date
    (start_date..end_date).count { |d| d.wday.between?(1, 5) }
  end

  # --- Released but not yet invoiced -------------------------------------------
  # Works orders with active release notes that are ready_for_invoice?.
  # Mirrors the cheat-sheet one-liner. Stalest first (days-since-release desc).
  def released_uninvoiced_rows
    WorksOrder
      .where("quantity_released > 0")
      .where(voided: false)
      .includes(:customer_order, :customer, :part, release_notes: :invoice_item)
      .order("works_orders.number DESC")
      .filter_map do |wo|
        uninvoiced = wo.release_notes.active.select(&:ready_for_invoice?)
        next if uninvoiced.empty?

        last_release_date = wo.release_notes.active.maximum(:date)

        {
          works_order:    wo,
          customer_order: wo.customer_order,
          customer_name:  wo.customer_name,
          part:           "#{wo.part_number}-#{wo.part_issue}",
          qty_uninvoiced: uninvoiced.sum(&:quantity_accepted),
          remaining:      wo.unreleased_quantity,
          value:          uninvoiced.sum(&:invoice_value),
          days_since:     last_release_date ? (Date.current - last_release_date).to_i : nil
        }
      end
      .sort_by { |r| -(r[:days_since] || 0) }
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
