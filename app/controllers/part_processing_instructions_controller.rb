# app/controllers/part_processing_instructions_controller.rb
class PartProcessingInstructionsController < ApplicationController
  before_action :set_ppi, only: [:show, :edit, :update, :destroy, :toggle_enabled]

  def index
    @ppis = PartProcessingInstruction.includes(:part, :customer)
                                   .enabled
                                   .order(created_at: :desc)

    # Filter by customer if provided
    if params[:customer_id].present?
      @ppis = @ppis.where(customer_id: params[:customer_id])
    end

    # Search by part number
    if params[:search].present?
      search_term = params[:search].upcase
      @ppis = @ppis.where(
        "part_number ILIKE ? OR part_issue ILIKE ? OR part_description ILIKE ?",
        "%#{search_term}%", "%#{search_term}%", "%#{search_term}%"
      )
    end

    # For the filter dropdown
    @customers = Organization.customers.enabled.order(:name)
  end

  def show
    @works_orders = @ppi.works_orders.includes(:customer_order, :release_level, :transport_method)
                        .order(created_at: :desc)
                        .limit(10)
  end

  def new
    @ppi = PartProcessingInstruction.new

    # If coming from a specific part, pre-populate
    if params[:part_id].present?
      @part = Part.find(params[:part_id])
      @ppi.part = @part
      @ppi.customer = @part.customer
      @ppi.part_number = @part.uniform_part_number
      @ppi.part_issue = @part.uniform_part_issue
      @ppi.part_description = "#{@part.uniform_part_number} component"
      @customers = [@part.customer] # Only show the part's customer
    else
      @part = nil
      @customers = Organization.customers.enabled.order(:name)
    end

    # Load process library options
    @alloy_options = ProcessLibrary.alloy_options
    @process_type_options = ProcessLibrary.process_type_options
    @class_options = ProcessLibrary.class_options

    # Handle process suggestion if parameters provided
    if params[:alloy].present? && params[:process_type].present?
      @suggested_processes = ProcessLibrary.suggest_processes(
        alloy: params[:alloy],
        process_type: params[:process_type],
        anodic_class: params[:anodic_class],
        target_thickness: params[:target_thickness]&.to_f
      )
    else
      @suggested_processes = []
    end
  end

  def create
    Rails.logger.info "🔍 Raw Params: #{params.inspect}"
    Rails.logger.info "🔍 PPI Params: #{ppi_params.inspect}"
    Rails.logger.info "🔍 Part ID from params: #{params[:part_id]}"

    @ppi = PartProcessingInstruction.new(ppi_params)

    # If coming from an existing part, set the part association directly
    if params[:part_id].present?
      @part = Part.find(params[:part_id])
      @ppi.part = @part
      @ppi.customer = @part.customer
      @ppi.part_number = @part.uniform_part_number
      @ppi.part_issue = @part.uniform_part_issue
      @ppi.part_description = @ppi.part_description.presence || "#{@part.uniform_part_number} component"
    end

    # Handle process selection
    if params[:selected_process_id].present?
      selected_process = ProcessLibrary.find(params[:selected_process_id])
      if selected_process
        @ppi.specification = selected_process.operation_text
        @ppi.process_type = selected_process.process_type
        Rails.logger.info "🔍 Applied process: #{selected_process.id} -> #{selected_process.operation_text}"
      end
    end

    Rails.logger.info "🔍 PPI before save: customer_id=#{@ppi.customer_id}, part_number=#{@ppi.part_number}, part_issue=#{@ppi.part_issue}, part=#{@ppi.part&.id}"

    # Set defaults for testing if not provided
    @ppi.process_type = 'hard_anodising' if @ppi.process_type.blank?
    @ppi.specification = "Process as per customer requirements for #{@ppi.part_number}-#{@ppi.part_issue}" if @ppi.specification.blank?
    @ppi.customisation_data = {} if @ppi.customisation_data.blank?

    if @ppi.save
      redirect_to @ppi, notice: 'Part processing instruction was successfully created.'
    else
      Rails.logger.error "🚨 PPI Save Errors: #{@ppi.errors.full_messages}"
      load_form_data_for_errors
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @customers = [@ppi.customer] # Don't allow changing customer
    @part = @ppi.part

    # Load process library options for editing
    @alloy_options = ProcessLibrary.alloy_options
    @process_type_options = ProcessLibrary.process_type_options
    @class_options = ProcessLibrary.class_options
    @suggested_processes = []
  end

  def update
    # Handle process selection on update
    if params[:selected_process_id].present?
      selected_process = ProcessLibrary.find(params[:selected_process_id])
      if selected_process
        @ppi.specification = selected_process.operation_text
        @ppi.process_type = selected_process.process_type
      end
    end

    if @ppi.update(ppi_params)
      redirect_to @ppi, notice: 'Part processing instruction was successfully updated.'
    else
      @customers = [@ppi.customer]
      @part = @ppi.part
      @alloy_options = ProcessLibrary.alloy_options
      @process_type_options = ProcessLibrary.process_type_options
      @class_options = ProcessLibrary.class_options
      @suggested_processes = []
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @ppi.can_be_deleted?
      @ppi.destroy
      redirect_to part_processing_instructions_url, notice: 'Part processing instruction was successfully deleted.'
    else
      redirect_to @ppi, alert: 'Cannot delete PPI with associated works orders.'
    end
  end

  def toggle_enabled
    @ppi.update!(enabled: !@ppi.enabled)
    status = @ppi.enabled? ? 'enabled' : 'disabled'
    redirect_to @ppi, notice: "PPI was successfully #{status}."
  end

  def search
    # AJAX endpoint for autocomplete functionality
    if params[:q].present?
      search_term = params[:q].upcase
      @ppis = PartProcessingInstruction.enabled
                                     .includes(:customer, :part)
                                     .where(
                                       "part_number ILIKE ? OR part_description ILIKE ?",
                                       "%#{search_term}%", "%#{search_term}%"
                                     )
                                     .limit(20)

      # Filter by customer if provided
      if params[:customer_id].present?
        @ppis = @ppis.where(customer_id: params[:customer_id])
      end
    else
      @ppis = PartProcessingInstruction.none
    end

    respond_to do |format|
      format.json do
        render json: @ppis.map { |ppi|
          {
            id: ppi.id,
            display_name: ppi.display_name,
            customer_name: ppi.customer.name,
            customer_id: ppi.customer_id,
            part_number: ppi.part_number,
            part_issue: ppi.part_issue,
            specification: ppi.specification
          }
        }
      end
      format.html { render :index }
    end
  end

  # NEW: AJAX endpoint for process suggestions
  def suggest_processes
    alloy = params[:alloy]
    process_type = params[:process_type]
    anodic_class = params[:anodic_class]
    target_thickness = params[:target_thickness]&.to_f

    if alloy.present? && process_type.present?
      @suggested_processes = ProcessLibrary.suggest_processes(
        alloy: alloy,
        process_type: process_type,
        anodic_class: anodic_class,
        target_thickness: target_thickness
      )
    else
      @suggested_processes = []
    end

    respond_to do |format|
      format.json do
        render json: @suggested_processes.map { |process|
          {
            id: process.id,
            display_name: process.display_name,
            target_thickness: process.target_thickness,
            anodic_classes: process.anodic_classes,
            vat_numbers: process.vat_numbers,
            operation_text: process.operation_text
          }
        }
      end
      format.html { render partial: 'process_suggestions', locals: { processes: @suggested_processes } }
    end
  end

  private

  def set_ppi
    @ppi = PartProcessingInstruction.find(params[:id])
  end

  def ppi_params
    params.require(:part_processing_instruction).permit(
      :customer_id, :part_number, :part_issue, :part_description,
      :specification, :special_instructions, :process_type, :enabled,
      :part_id
    )
  end

  def load_form_data_for_errors
    if params[:part_id].present?
      @part = Part.find(params[:part_id])
      @customers = [@part.customer]
    else
      @part = nil
      @customers = Organization.customers.enabled.order(:name)
    end

    # Reload process library options
    @alloy_options = ProcessLibrary.alloy_options
    @process_type_options = ProcessLibrary.process_type_options
    @class_options = ProcessLibrary.class_options
    @suggested_processes = []
  end
end
