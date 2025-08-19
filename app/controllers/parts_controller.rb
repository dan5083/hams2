class PartsController < ApplicationController
  before_action :set_part, only: [:show, :edit, :update, :destroy, :toggle_enabled]

  def index
    @parts = Part.includes(:customer, :part_processing_instructions, :works_orders)
                 .order(:uniform_part_number, :uniform_part_issue)

    # Filter by customer if provided
    if params[:customer_id].present?
      @parts = @parts.for_customer(params[:customer_id])
    end

    # Filter by enabled status
    case params[:status]
    when 'enabled'
      @parts = @parts.enabled
    when 'disabled'
      @parts = @parts.where(enabled: false)
    end

    # Search by part number or issue
    if params[:search].present?
      search_term = Part.make_uniform(params[:search])
      @parts = @parts.where(
        "uniform_part_number ILIKE ? OR uniform_part_issue ILIKE ?",
        "%#{search_term}%", "%#{search_term}%"
      )
    end

    # For the filter dropdown - show all organizations
    @customers = Organization.enabled.order(:name)
  end

  def show
    @part_processing_instructions = @part.part_processing_instructions
                                         .includes(:customer)
                                         .order(created_at: :desc)
    @works_orders = @part.works_orders
                         .includes(:customer_order, :release_level, :transport_method)
                         .order(created_at: :desc)
                         .limit(10) # Show recent works orders
  end

  def new
    @part = Part.new
    @customers = Organization.enabled.order(:name)
  end

  def create
    # Use Part.ensure to find or create the part
    @part = Part.ensure(
      customer_id: part_params[:customer_id],
      part_number: part_params[:uniform_part_number],
      part_issue: part_params[:uniform_part_issue]
    )

    if @part.persisted?
      if @part.enabled?
        redirect_to @part, notice: 'Part already exists and is enabled.'
      else
        @part.update!(enabled: true)
        redirect_to @part, notice: 'Part was re-enabled successfully.'
      end
    else
      redirect_to @part, notice: 'Part was successfully created.'
    end
  rescue ActiveRecord::RecordInvalid
    @customers = Organization.enabled.order(:name)
    render :new, status: :unprocessable_entity
  end

  def edit
    @customers = Organization.enabled.order(:name)
  end

  def update
    # For parts, we mainly just update the enabled status
    # Part number and issue changes would create a new part via Part.ensure
    if params[:part][:uniform_part_number] != @part.uniform_part_number ||
       params[:part][:uniform_part_issue] != @part.uniform_part_issue ||
       params[:part][:customer_id] != @part.customer_id.to_s

      # This is effectively creating a new part
      new_part = Part.ensure(
        customer_id: part_params[:customer_id],
        part_number: part_params[:uniform_part_number],
        part_issue: part_params[:uniform_part_issue]
      )

      redirect_to new_part, notice: 'Part details updated - redirected to the correct part record.'
    elsif @part.update(enabled: part_params[:enabled])
      redirect_to @part, notice: 'Part was successfully updated.'
    else
      @customers = Organization.enabled.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @part.can_be_deleted?
      @part.destroy
      redirect_to parts_url, notice: 'Part was successfully deleted.'
    else
      redirect_to @part, alert: 'Cannot delete part with associated processing instructions or works orders.'
    end
  end

  def toggle_enabled
    @part.update!(enabled: !@part.enabled)
    status = @part.enabled? ? 'enabled' : 'disabled'
    redirect_to @part, notice: "Part was successfully #{status}."
  end

  def search
    # AJAX endpoint for autocomplete/search functionality
    if params[:q].present?
      search_term = Part.make_uniform(params[:q])
      @parts = Part.enabled
                   .includes(:customer)
                   .where(
                     "uniform_part_number ILIKE ? OR uniform_part_issue ILIKE ?",
                     "%#{search_term}%", "%#{search_term}%"
                   )
                   .limit(20)

      # Filter by customer if provided
      if params[:customer_id].present?
        @parts = @parts.for_customer(params[:customer_id])
      end
    else
      @parts = Part.none
    end

    respond_to do |format|
      format.json do
        render json: @parts.map { |part|
          {
            id: part.id,
            display_name: part.display_name,
            customer_name: part.customer.name,
            customer_id: part.customer_id
          }
        }
      end
      format.html { render :index }
    end
  end

  private

  def set_part
    @part = Part.find(params[:id])
  end

  def part_params
    params.require(:part).permit(:customer_id, :uniform_part_number, :uniform_part_issue, :enabled)
  end
end
