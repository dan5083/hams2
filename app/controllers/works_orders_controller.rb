class WorksOrdersController < ApplicationController
  before_action :set_works_order, only: [:show, :edit, :update, :destroy, :route_card]

  def index
    @works_orders = WorksOrder.includes(:customer_order, :part, :release_level, :transport_method)
                              .active
                              .order(created_at: :desc)

    # Add filtering if needed
    if params[:customer_id].present?
      @works_orders = @works_orders.for_customer(params[:customer_id])
    end

    if params[:status] == 'open'
      @works_orders = @works_orders.open
    elsif params[:status] == 'closed'
      @works_orders = @works_orders.closed
    end
  end

  def show
  end

  def new
    @works_order = WorksOrder.new
    @customer_orders = CustomerOrder.active.includes(:customer).order(created_at: :desc)
    @parts = Part.enabled.includes(:customer).order(:uniform_part_number)
    @release_levels = ReleaseLevel.enabled.ordered
    @transport_methods = TransportMethod.enabled.ordered
    @ppis = PartProcessingInstruction.enabled.includes(:customer, :part)
  end

  def create
    @works_order = WorksOrder.new(works_order_params)

    if @works_order.save
      redirect_to @works_order, notice: 'Works order was successfully created.'
    else
      load_form_data
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_form_data
  end

  def update
    if @works_order.update(works_order_params)
      redirect_to @works_order, notice: 'Works order was successfully updated.'
    else
      load_form_data
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @works_order.can_be_deleted?
      @works_order.destroy
      redirect_to works_orders_url, notice: 'Works order was successfully deleted.'
    else
      redirect_to @works_order, alert: 'Cannot delete works order with associated release notes.'
    end
  end

  def route_card
    @operations = build_operations_from_process(@works_order)

    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        # If using wicked_pdf or similar
        render pdf: "route_card_wo#{@works_order.number}",
               layout: false,
               template: 'works_orders/route_card'
      end
    end
  end

  def complete
    @works_order = WorksOrder.find(params[:id])

    if @works_order.can_be_completed?
      @works_order.complete!(Current.user)
      redirect_to @works_order, notice: 'Works order completed successfully.'
    else
      redirect_to @works_order, alert: 'Cannot complete works order - insufficient quantity released.'
    end
  end

  private

  def set_works_order
    @works_order = WorksOrder.find(params[:id])
  end

  def works_order_params
    params.require(:works_order).permit(
      :customer_order_id, :part_id, :release_level_id, :transport_method_id,
      :ppi_id, :due_date, :quantity, :lot_price, :each_price, :price_type,
      :part_number, :part_issue, :part_description
    )
  end

  def load_form_data
    @customer_orders = CustomerOrder.active.includes(:customer).order(created_at: :desc)
    @parts = Part.enabled.includes(:customer).order(:uniform_part_number)
    @release_levels = ReleaseLevel.enabled.ordered
    @transport_methods = TransportMethod.enabled.ordered
    @ppis = PartProcessingInstruction.enabled.includes(:customer, :part)
  end

  def generate_qr_code(data)
    # QR code functionality removed - feature never took off
    nil
  end

  def build_operations_from_process(works_order)
    # This method should build the operations array from the works order's
    # customised_process_data. The structure should match what your templates expect.
    # This is a placeholder - you'll need to implement based on your ProcessBuilder logic

    process_data = works_order.customised_process_data || {}
    operations = []

    # Example structure - adapt based on your actual process data format
    if process_data['operations']
      process_data['operations'].each_with_index do |op_data, index|
        operations << {
          number: index + 1,
          content: [
            {
              type: 'paragraph',
              as_html: op_data['description'] || 'Operation description'
            }
          ],
          all_variables: op_data['variables'] || []
        }
      end
    else
      # Default single operation if no process data
      operations << {
        number: 1,
        content: [
          {
            type: 'paragraph',
            as_html: works_order.specification || 'Process as per specification'
          }
        ],
        all_variables: []
      }
    end

    operations
  end
end
