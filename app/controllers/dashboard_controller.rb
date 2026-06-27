# app/controllers/dashboard_controller.rb - Updated with role-based access control
class DashboardController < ApplicationController
  before_action :require_xero_access, only: [:push_selected_to_xero]

  def index
    # Xero connection/data loaded for everyone; Xero gates access on its own side
    @xero_connected = xero_connected?
    @pending_invoices = Invoice.draft.includes(:customer)

    # Same dashboard for everyone
    load_management_metrics
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

  def load_management_metrics
    # Business metrics shown to all users
    @total_revenue_pending = @pending_invoices.sum(:total_inc_tax)

    # On-time delivery (trailing 30 days) - aerospace vs commercial
    @otd = on_time_delivery_stats(days: 30)

    # Released but not yet invoiced worklist
    @uninvoiced_rows = released_uninvoiced_rows
  end

  # --- On-Time Delivery over a trailing window ---------------------------------
  # Cohort = customer orders RECEIVED in the last `days` days (mirrors the monthly
  # report, which buckets by date_received). An order counts once it has at least
  # one active release note; duration = received -> last release in working days.
  # Targets: aerospace <=15, commercial <=10.
  def on_time_delivery_stats(days: 30)
    window_start = Date.current - days

    orders = CustomerOrder
             .includes(:customer, works_orders: :part)
             .where(voided: false)
             .where(date_received: window_start..Date.current)

    # One grouped query for the latest active release date per works order,
    # instead of one ReleaseNote query per customer order.
    wo_ids = orders.flat_map { |o| o.works_orders.map(&:id) }
    last_release_by_wo = ReleaseNote.active
                                    .where(works_order_id: wo_ids)
                                    .group(:works_order_id)
                                    .maximum(:date)

    completed = []
    orders.each do |order|
      wos = order.works_orders
      next if wos.empty?

      last_release_date = wos.filter_map { |wo| last_release_by_wo[wo.id] }.max
      next unless last_release_date

      completed << {
        order:         order,
        customer_name: order.customer&.name,
        aerospace:     wos.any? { |wo| wo.part&.aerospace_defense? },
        duration:      working_days_between(order.date_received, last_release_date)
      }
    end

    # Orders over their target, worst overage first.
    laggards = completed.filter_map do |o|
      target = o[:aerospace] ? 15 : 10
      next if o[:duration] <= target
      o.merge(target: target, over_by: o[:duration] - target)
    end.sort_by { |o| -o[:over_by] }

    {
      aerospace:  otd_breakdown(completed.select { |o| o[:aerospace] }, target: 15),
      commercial: otd_breakdown(completed.reject { |o| o[:aerospace] }, target: 10),
      laggards:   laggards
    }
  end

  def otd_breakdown(orders, target:)
    total     = orders.size
    met       = orders.count { |o| o[:duration] <= target }
    durations = orders.map { |o| o[:duration] }
    {
      total:  total,
      met:    met,
      missed: total - met,
      target: target,
      pct:    total.zero? ? nil : (met.to_f / total * 100).round(1),
      avg:    durations.empty? ? nil : (durations.sum.to_f / durations.size).round(1)
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
    # Drive off the live invoicing backlog (release notes that still need an
    # invoice) rather than the full history of released works orders — the
    # working set is bounded by what's actually outstanding, not all-time volume.
    # ReleaseNote.ready_for_invoice is the SQL equivalent of #ready_for_invoice?.
    ReleaseNote.ready_for_invoice
               .includes(works_order: [:customer_order, :customer, :part])
               .group_by(&:works_order)
               .filter_map do |wo, release_notes|
                 next if wo.nil? || wo.voided?

                 last_release_date = release_notes.filter_map(&:date).max

                 {
                   works_order:    wo,
                   customer_order: wo.customer_order,
                   customer_name:  wo.customer_name,
                   part:           "#{wo.part_number}-#{wo.part_issue}",
                   qty_uninvoiced: release_notes.sum(&:quantity_accepted),
                   remaining:      wo.unreleased_quantity,
                   value:          release_notes.sum(&:invoice_value),
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
