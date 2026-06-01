class CustomerOrdersController < ApplicationController
  before_action :set_customer_order, only: [:show, :edit, :update, :destroy, :void, :create_invoice,
                                            :mark_contract_reviewed, :unmark_contract_reviewed]

  def index
    @customer_orders = CustomerOrder.includes(:customer, :works_orders)

    if params[:customer_id].present?
      @customer_orders = @customer_orders.for_customer(params[:customer_id])
    end

    case params[:status]
    when 'outstanding'
      @customer_orders = @customer_orders.outstanding
    when 'voided'
      @customer_orders = @customer_orders.voided
    when 'active'
      @customer_orders = @customer_orders.active
    end

    if params[:search].present?
      search_term = params[:search].strip
      @customer_orders = @customer_orders.joins(:customer)
                                        .where(
                                          "customer_orders.number ILIKE ? OR organizations.name ILIKE ?",
                                          "%#{search_term}%", "%#{search_term}%"
                                        )
    end

    @customers = Organization.enabled.order(:name)

    # Priority ordering for the list. Lower number = higher up the page.
    #   0  Green  - all WOs fully released and there's uninvoiced qty -> "Create invoice"
    #   1  Purple - contract not yet reviewed AND has a new-part WO    -> "Review needed"
    #   2  Partial release in progress
    #   3  Everything else (default)
    #   4  Open but nothing left to invoice
    #   5  Voided
    #
    # Green is tested before Purple so an order that is BOTH ready-to-invoice and
    # review-needed still sorts (and renders) green, matching the view's
    # "green takes precedence" rule.
    #
    # The Purple/"needs review" test here mirrors EXACTLY the definition used to
    # build @cos_with_new_parts below (and in the view): contract not reviewed,
    # plus a non-voided WO whose part has only ever appeared on one WO (<= 1).
    # If that definition ever changes, change it in BOTH places.
    @customer_orders = @customer_orders.order(
      Arel.sql("
        CASE
          WHEN customer_orders.voided = true THEN 5
          WHEN customer_orders.fully_released_works_orders_count = customer_orders.open_works_orders_count
               AND customer_orders.open_works_orders_count > 0
               AND customer_orders.uninvoiced_accepted_quantity > 0 THEN 0
          WHEN customer_orders.contract_reviewed_by_user_id IS NULL
               AND EXISTS (
                 SELECT 1 FROM works_orders w
                 WHERE w.customer_order_id = customer_orders.id
                   AND w.voided = false
                   AND (SELECT COUNT(*) FROM works_orders w2 WHERE w2.part_id = w.part_id) <= 1
               ) THEN 1
          WHEN customer_orders.open_works_orders_count > 0
               AND customer_orders.fully_released_works_orders_count > 0
               AND customer_orders.fully_released_works_orders_count < customer_orders.open_works_orders_count THEN 2
          WHEN customer_orders.open_works_orders_count > 0
               AND customer_orders.uninvoiced_accepted_quantity = 0 THEN 4
          ELSE 3
        END
      "),
      date_received: :desc
    ).page(params[:page]).per(20)

    # Build set of customer order IDs that have at least one new-part WO —
    # used to highlight orders needing contract review before route cards can print.
    # Two queries regardless of page size; no per-row lookups.
    co_ids = @customer_orders.map(&:id)
    wo_part_data = WorksOrder.where(customer_order_id: co_ids, voided: false)
                             .pluck(:customer_order_id, :part_id)
    part_ids = wo_part_data.map(&:last).uniq
    part_wo_counts = WorksOrder.where(part_id: part_ids).group(:part_id).count
    @cos_with_new_parts = Set.new
    wo_part_data.each do |co_id, part_id|
      @cos_with_new_parts << co_id if (part_wo_counts[part_id] || 0) <= 1
    end
  end

  def show
    @works_orders = @customer_order.works_orders
                                   .includes(:part)
                                   .order(created_at: :desc)

    # Fetch part WO counts in one query rather than once per row
    part_ids = @works_orders.map(&:part_id).compact
    @part_wo_counts = WorksOrder.where(part_id: part_ids)
                                .group(:part_id)
                                .count
  end

  def new
    @customer_order = CustomerOrder.new
    @customers = Organization.enabled.order(:name)
  end

  def create
    @customer_order = CustomerOrder.new(customer_order_params)

    if @customer_order.save
      redirect_to @customer_order, notice: 'Customer order was successfully created.'
    else
      @customers = Organization.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def create_invoice
    active_works_orders = @customer_order.works_orders.active

    if active_works_orders.empty?
      redirect_to customer_orders_path, alert: 'No active works orders found for this customer order.'
      return
    end

    incomplete_works_orders = active_works_orders.select { |wo| wo.quantity_released < wo.quantity }

    if incomplete_works_orders.any?
      incomplete_list = incomplete_works_orders.map { |wo| "WO#{wo.number}" }.join(', ')
      redirect_to customer_orders_path,
                  alert: "Cannot create invoice - not all works orders are fully released. Incomplete: #{incomplete_list}. Please complete all releases first."
      return
    end

    total_released = active_works_orders.sum(:quantity_released)

    if total_released <= 0
      redirect_to customer_orders_path, alert: 'No items available to invoice - no quantity has been released for this customer order yet.'
      return
    end

    begin
      uninvoiced_release_notes = ReleaseNote.joins(:works_order)
                                            .where(works_orders: { customer_order_id: @customer_order.id })
                                            .requires_invoicing

      if uninvoiced_release_notes.empty?
        redirect_to customer_orders_path, alert: 'No release notes available for invoicing. All items may already be invoiced.'
        return
      end

      customer = @customer_order.customer
      invoice = Invoice.create_from_release_notes(uninvoiced_release_notes, customer, Current.user)

      if invoice.nil?
        redirect_to customer_orders_path, alert: 'Failed to create invoice from release notes. Check logs for details.'
        return
      end

      @customer_order.works_orders.active.each do |works_order|
        if works_order.selected_charge_ids.present?
          add_additional_charges_to_invoice(invoice, works_order.selected_charge_ids, works_order.custom_amounts || {})
        end
      end

      invoice.calculate_totals!

      works_order_count = uninvoiced_release_notes.joins(:works_order).select('works_orders.id').distinct.count
      release_note_count = uninvoiced_release_notes.count
      summary = "Invoice created for fully completed customer order #{@customer_order.number} (#{works_order_count} works orders, #{release_note_count} release notes)"

      redirect_to customer_orders_path,
                  notice: "✅ Invoice INV#{invoice.number} staged successfully! #{summary}. Go to dashboard to push to Xero."

    rescue StandardError => e
      Rails.logger.error "Failed to create invoice for customer order #{@customer_order.id}: #{e.message}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"

      redirect_to customer_orders_path,
                  alert: "❌ Failed to stage invoice: #{e.message}. Please try again or contact support."
    end
  end

  def edit
    @customers = Organization.enabled.order(:name)
  end

  def update
    if @customer_order.update(customer_order_params)
      redirect_to @customer_order, notice: 'Customer order was successfully updated.'
    else
      @customers = Organization.enabled.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @customer_order.can_be_deleted?
      @customer_order.destroy
      redirect_to customer_orders_url, notice: 'Customer order was successfully deleted.'
    else
      redirect_to @customer_order, alert: 'Cannot delete customer order with associated works orders.'
    end
  end

  def void
    begin
      @customer_order.void!
      redirect_to @customer_order, notice: 'Customer order was successfully voided.'
    rescue StandardError => e
      redirect_to @customer_order, alert: e.message
    end
  end

  def mark_contract_reviewed
    @customer_order.mark_contract_reviewed!(Current.user)
    redirect_to @customer_order, notice: "Contract marked as reviewed by #{Current.user.display_name}."
  end

  def unmark_contract_reviewed
    @customer_order.unmark_contract_reviewed!
    redirect_to @customer_order, notice: 'Contract review cleared.'
  end

  def search_customers
    if params[:q].present?
      search_term = params[:q].strip
      @customers = Organization.enabled
                               .where("name ILIKE ?", "%#{search_term}%")
                               .order(:name)
                               .limit(10)
    else
      @customers = Organization.none
    end

    respond_to do |format|
      format.json do
        render json: @customers.map { |customer|
          {
            id: customer.id,
            name: customer.name,
            display_text: customer.name
          }
        }
      end
    end
  end

  private

  def set_customer_order
    @customer_order = CustomerOrder.find(params[:id])
  end

  def add_additional_charges_to_invoice(invoice, charge_ids, custom_amounts)
    charge_ids.reject(&:blank?).each do |charge_id|
      charge = AdditionalChargePreset.find(charge_id)
      custom_amount = custom_amounts[charge_id]
      InvoiceItem.create_from_additional_charge(charge, invoice, custom_amount)
    end
  end

  def customer_order_params
    params.require(:customer_order).permit(
      :customer_id,
      :number,
      :date_received
    )
  end
end
