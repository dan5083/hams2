class CustomerOrdersController < ApplicationController
  before_action :set_customer_order, only: [:show, :edit, :update, :destroy, :void,
                                            :invoice_to_date]

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
    #   0  Green  - money on the table: released work not yet invoiced
    #   3  Everything else (default)
    #   5  Voided
    #
    # This deliberately sorts on uninvoiced_accepted_quantity ALONE. The older
    # tiers keyed off open_works_orders_count / fully_released_works_orders_count
    # were dead code: both counters filter is_open: true (see
    # app/models/concerns/customer_order_counter_cache.rb), so once a works order
    # closes on full release they drop to zero and no order could ever satisfy
    # "fully released count == open count AND open count > 0". Every row fell
    # through to tier 3. Don't reintroduce them here without fixing the concern
    # first — CustomerOrder#fully_released? is the trustworthy check, but it's a
    # per-record query and can't be used for SQL ordering.
    #
    # (Contract review lives on the works order's contract review operation;
    #  the old CO-level "Review needed" purple tier is gone.)
    @customer_orders = @customer_orders.order(
      Arel.sql("
        CASE
          WHEN customer_orders.voided = true THEN 5
          WHEN customer_orders.uninvoiced_accepted_quantity > 0 THEN 0
          ELSE 3
        END
      "),
      date_received: :desc
    ).page(params[:page]).per(20)
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

    # Route card vs 📱 Paperless per row
    @paperless_wo_ids = WorksOrder.paperless_ids(@works_orders)
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

  # Invoice everything released TO DATE on this customer order (partial orders
  # are fine — no "all WOs fully released" gate). Drives off requires_invoicing
  # release notes via Invoice.stage_to_date, which bills courier per release note
  # and is safe to call repeatedly. Triggered by the 🐓 button on the dashboard
  # "Released but Uninvoiced" worklist.
  #
  # NOTE: the customer orders index used to carry a "Create Invoice" button that
  # also hit this action. That button was gated on the broken counter columns, so
  # it had silently stopped rendering; it's been removed rather than repaired
  # because the dashboard worklist is where invoicing actually gets triggered.
  # The action keeps its return_to handling so it can be called from anywhere.
  #
  # Redirect target: honours an optional return_to param (relative paths only,
  # see safe_return_path). When no return_to is supplied (e.g. the dashboard 🐓
  # button) it falls back to root_path, preserving the dashboard behaviour.
  def invoice_to_date
    return_path = safe_return_path(params[:return_to]) || root_path

    release_notes = ReleaseNote.joins(:works_order)
                               .where(works_orders: { customer_order_id: @customer_order.id })
                               .requires_invoicing

    invoice = Invoice.stage_to_date(release_notes, Current.user)

    if invoice
      redirect_to return_path,
                  notice: "✅ Invoice INV#{invoice.number} staged for order #{@customer_order.number} (released to date). Push to Xero from the dashboard."
    else
      redirect_to return_path,
                  alert: "Nothing to invoice on order #{@customer_order.number} — it may already be invoiced to date."
    end
  rescue StandardError => e
    Rails.logger.error "invoice_to_date (CO #{@customer_order.id}) failed: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to return_path, alert: "❌ Failed to stage invoice: #{e.message}"
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

  # Only allow local, relative return paths ("/customer_orders?page=2") so a
  # crafted return_to can't turn this into an open redirect ("//evil.com" or
  # "https://evil.com"). Returns nil for anything unsafe/blank so callers can
  # fall back to their default.
  def safe_return_path(path)
    return if path.blank?
    path if path.start_with?("/") && !path.start_with?("//")
  end

  def customer_order_params
    params.require(:customer_order).permit(
      :customer_id,
      :number,
      :date_received
    )
  end
end
