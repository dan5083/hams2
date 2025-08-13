class CustomerOrdersController < ApplicationController
  before_action :set_customer_order, only: [:show, :edit, :update, :destroy, :void]

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

    # For the filter dropdown
    @customers = Organization.customers.enabled.order(:name)
  end

  def show
    @works_orders = @customer_order.works_orders
                                   .includes(:part, :release_level, :transport_method)
                                   .order(created_at: :desc)
  end

  def new
    @customer_order = CustomerOrder.new
    @customers = Organization.customers.enabled.order(:name)
  end

  def create
    @customer_order = CustomerOrder.new(customer_order_params)

    if @customer_order.save
      redirect_to @customer_order, notice: 'Customer order was successfully created.'
    else
      @customers = Organization.customers.enabled.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @customers = Organization.customers.enabled.order(:name)
  end

  def update
    if @customer_order.update(customer_order_params)
      redirect_to @customer_order, notice: 'Customer order was successfully updated.'
    else
      @customers = Organization.customers.enabled.order(:name)
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

  def customer_order_params
    params.require(:customer_order).permit(
      :customer_id,
      :number,
      :date_received,
      :notes,
      :customer_reference,
      :delivery_required_date,
      :special_requirements
    )
  end
end
