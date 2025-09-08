class CustomerOrdersController < ApplicationController
  before_action :set_customer_order, only: [:show, :edit, :update, :destroy, :void, :create_invoice]

  def index
    @customer_orders = CustomerOrder.includes(:customer, :works_orders)
                                   .order(date_received: :desc)

    # Filter by customer if provided
    if params[:customer_id].present?
      @customer_orders = @customer_orders.for_customer(params[:customer_id])
    end

    # Filter by status
    case params[:status]
    when 'outstanding'
      @customer_orders = @customer_orders.outstanding
    when 'voided'
      @customer_orders = @customer_orders.voided
    when 'active'
      @customer_orders = @customer_orders.active
    end

    # Search by order number
    if params[:search].present?
      @customer_orders = @customer_orders.where(
        "number ILIKE ?", "%#{params[:search]}%"
      )
    end

    # For the filter dropdown - include all enabled organizations
    @customers = Organization.enabled.order(:name)
  end

  def show
    @works_orders = @customer_order.works_orders
                                   .includes(:part, :release_level, :transport_method)
                                   .order(created_at: :desc)
  end

  def new
    @customer_order = CustomerOrder.new
    # Include all enabled organizations, not just those marked as customers
    @customers = Organization.enabled.order(:name)
  end

  def create
    @customer_order = CustomerOrder.new(customer_order_params)

    if @customer_order.save
      redirect_to @customer_order, notice: 'Customer order was successfully created.'
    else
      # Include all enabled organizations, not just those marked as customers
      @customers = Organization.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def create_invoice
  # Check if any quantity has been released
  total_released = @customer_order.works_orders.active.sum(:quantity_released)

  if total_released <= 0
    redirect_to @customer_order, alert: 'No items available to invoice - no quantity has been released for this customer order yet.'
    return
  end

  begin
    # Get all uninvoiced release notes for this customer order
    uninvoiced_release_notes = ReleaseNote.joins(:works_order)
                                         .where(works_orders: { customer_order_id: @customer_order.id })
                                         .requires_invoicing

    if uninvoiced_release_notes.empty?
      redirect_to @customer_order, alert: 'No release notes available for invoicing. All items may already be invoiced.'
      return
    end

    # Create invoice from all uninvoiced release notes
    customer = @customer_order.customer

    invoice = Invoice.create_from_release_notes(uninvoiced_release_notes, customer, Current.user)

    if invoice.nil?
      redirect_to @customer_order, alert: 'Failed to create invoice from release notes. Check logs for details.'
      return
    end

    # Add additional charges from all works orders in this customer order
    @customer_order.works_orders.active.each do |works_order|
      if works_order.selected_charge_ids.present?
        add_additional_charges_to_invoice(invoice, works_order.selected_charge_ids, works_order.custom_amounts || {})
      end
    end

    # Recalculate totals after adding all charges
    invoice.calculate_totals!

    # Build summary message
    works_order_count = uninvoiced_release_notes.joins(:works_order).select('works_orders.id').distinct.count
    release_note_count = uninvoiced_release_notes.count

    summary = "Invoice created for customer order #{@customer_order.number} (#{works_order_count} works orders, #{release_note_count} release notes)"

    redirect_to @customer_order,
                notice: "✅ Invoice INV#{invoice.number} staged successfully! #{summary}. Go to dashboard to push to Xero."

  rescue StandardError => e
    Rails.logger.error "Failed to create invoice for customer order #{@customer_order.id}: #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"

    redirect_to @customer_order,
                alert: "❌ Failed to stage invoice: #{e.message}. Please try again or contact support."
  end
end


  def edit
    # Include all enabled organizations, not just those marked as customers
    @customers = Organization.enabled.order(:name)
  end

  def update
    if @customer_order.update(customer_order_params)
      redirect_to @customer_order, notice: 'Customer order was successfully updated.'
    else
      # Include all enabled organizations, not just those marked as customers
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
  end  # <-- This end was missing

  def customer_order_params
    params.require(:customer_order).permit(
      :customer_id,
      :number,
      :date_received
    )
  end
