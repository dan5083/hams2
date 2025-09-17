class PartsController < ApplicationController
before_action :set_part, only: [:show, :edit, :update, :destroy, :toggle_enabled, :insert_operation, :reorder_operation, :delete_operation]

  def index
    @parts = Part.includes(:customer, :works_orders)
                 .order(:part_number, :part_issue)

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
      search_term = params[:search].upcase.strip
      @parts = @parts.where(
        "UPPER(part_number) ILIKE ? OR UPPER(part_issue) ILIKE ?",
        "%#{search_term}%", "%#{search_term}%"
      )
    end

    # For the filter dropdown - show all organizations
    @customers = Organization.enabled.order(:name)
  end

  def show
    @works_orders = @part.works_orders
                         .includes(:customer_order, :release_level, :transport_method)
                         .order(created_at: :desc)
                         .limit(10) # Show recent works orders
  end

  def new
    @part = Part.new
    @customers = Organization.enabled.order(:name)
    @specification_presets = SpecificationPreset.enabled.ordered

    # Pre-select customer if coming from works order form
    if params[:customer_id].present?
      @part.customer_id = params[:customer_id]
    end

    # Set up for complex form (formerly PPI form)
    @part.customisation_data = { "operation_selection" => {} }
  end

 def create
  @part = Part.new(part_params)

  # Set defaults for new parts with processing instructions
  @part.process_type = determine_process_type if @part.process_type.blank?

  # NEW: Check validation BEFORE manual mode switch
  if params[:switch_to_manual] == 'true'
    unless @part.valid?
      load_form_data_for_errors
      render :new, status: :unprocessable_entity
      return
    end

    # Handle manual mode switch - generate operations and lock them before save
    begin
      # Check if we have locked_operations from the copy functionality
      if params[:locked_operations].present?
        # Convert ActionController::Parameters to hash and then map
        locked_operations_hash = params[:locked_operations].to_unsafe_h
        display_names_hash = params[:locked_operations_display_names]&.to_unsafe_h || {}

        locked_ops = locked_operations_hash.map do |position, operation_text|
          display_name = display_names_hash[position] || "Operation #{position}"
          {
            "id" => "COPIED_OP_#{position}",
            "display_name" => display_name,  # Use the proper display name
            "operation_text" => operation_text.to_s,
            "position" => position.to_i,
            "specifications" => "",
            "vat_numbers" => [],
            "process_type" => "manual",
            "target_thickness" => 0,
            "auto_inserted" => false
          }
        end.sort_by { |op| op["position"] }

      else
        # Generate operations from current configuration (original behavior)
        current_ops = @part.get_operations_with_auto_ops

        if current_ops.empty?
          @part.errors.add(:base, "No operations found to switch to manual mode. Please configure treatments first.")
          load_form_data_for_errors
          render :new, status: :unprocessable_entity
          return
        end

        locked_ops = current_ops.map.with_index do |op, index|
          {
            "id" => op.id,
            "display_name" => op.display_name,
            "operation_text" => op.operation_text,
            "position" => index + 1,
            "specifications" => op.respond_to?(:specifications) ? (op.specifications || '') : '',
            "vat_numbers" => op.respond_to?(:vat_numbers) ? (op.vat_numbers || []) : [],
            "process_type" => op.respond_to?(:process_type) ? op.process_type : 'manual',
            "target_thickness" => op.respond_to?(:target_thickness) ? (op.target_thickness || 0) : 0,
            "auto_inserted" => op.respond_to?(:auto_inserted?) ? op.auto_inserted? : false
          }
        end
      end

      # Lock the operations before saving
      @part.customisation_data = @part.customisation_data.dup || {}
      @part.customisation_data["operation_selection"] ||= {}
      @part.customisation_data["operation_selection"]["locked"] = true
      @part.customisation_data["operation_selection"]["locked_operations"] = locked_ops

    rescue => e
      @part.errors.add(:base, "Failed to switch to manual mode: #{e.message}")
      load_form_data_for_errors
      render :new, status: :unprocessable_entity
      return
    end
  end

  if @part.save
    if params[:switch_to_manual] == 'true'
      redirect_to edit_part_path(@part), notice: 'Part created and switched to manual editing mode. You can now customize each operation.'
    else
      redirect_to @part, notice: 'Part was successfully created.'
    end
  else
    load_form_data_for_errors
    render :new, status: :unprocessable_entity
  end
end

  def edit
    @customers = [@part.customer] # Don't allow changing customer on existing part
    @specification_presets = SpecificationPreset.enabled.ordered

    # Auto-lock existing parts that don't have the locked operations structure
    if @part.persisted? && !@part.has_locked_operations_data?
      @part.auto_lock_for_editing!
    end

    # Ensure customisation_data structure exists for unlocked parts (shouldn't happen for persisted parts)
    if !@part.locked_for_editing?
      @part.customisation_data = { "operation_selection" => {} } if @part.customisation_data.blank?
    end
  end

  def update
    # Handle manual mode switch for existing parts
    if params[:switch_to_manual] == 'true'
      begin
        # Generate operations from current configuration
        current_ops = @part.get_operations_with_auto_ops

        if current_ops.empty?
          redirect_to edit_part_path(@part), alert: 'No operations found to switch to manual mode. Please configure treatments first.'
          return
        end

        # Update with new data first, then lock operations
        if @part.update(part_params)
          # Auto-lock will happen due to the callback
          redirect_to edit_part_path(@part), notice: 'Part updated and switched to manual editing mode.'
          return
        else
          @customers = [@part.customer]
          @specification_presets = SpecificationPreset.enabled.ordered
          render :edit, status: :unprocessable_entity
          return
        end

      rescue => e
        redirect_to edit_part_path(@part), alert: "Failed to switch to manual mode: #{e.message}"
        return
      end
    end

    # Handle locked operations updates (text changes only)
    if @part.locked_for_editing? && params[:locked_operations].present?
      # FIRST update the part details
      if @part.update(part_params)
        # THEN update the locked operations text
        if update_locked_operations_text
          redirect_to @part, notice: 'Part and operations were successfully updated.'
        else
          @customers = [@part.customer]
          @specification_presets = SpecificationPreset.enabled.ordered
          render :edit, status: :unprocessable_entity
        end
      else
        @customers = [@part.customer]
        @specification_presets = SpecificationPreset.enabled.ordered
        render :edit, status: :unprocessable_entity
      end
      return
    end

    # Standard update - just update the part directly
    if @part.update(part_params)
      redirect_to @part, notice: 'Part was successfully updated.'
    else
      @customers = [@part.customer]
      @specification_presets = SpecificationPreset.enabled.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @part.can_be_deleted?
      @part.destroy
      redirect_to parts_url, notice: 'Part was successfully deleted.'
    else
      redirect_to @part, alert: 'Cannot delete part with associated works orders.'
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
      search_term = params[:q].upcase.strip
      @parts = Part.enabled
                  .includes(:customer)
                  .where(
                    "UPPER(part_number) ILIKE ? OR UPPER(part_issue) ILIKE ?",
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
            customer_id: part.customer_id,
            specification: part.specification,
            operations_summary: part.operations_summary
          }
        }
      end
      format.html { render :index }
    end
  end

  # Operations endpoints for the complex treatment form (formerly PPI endpoints)
  def filter_operations
    criteria = filter_params

    # Extract thickness for ENP operations
    target_thickness = criteria[:target_thicknesses]&.first

    # Start with all operations - pass thickness to ENP operations
    operations = Operation.all_operations(target_thickness)

    # Filter by anodising types - include stripping_only and exclude auto-inserted operations
    if criteria[:anodising_types].present?
      # Handle stripping_only as a special case
      if criteria[:anodising_types].include?('stripping_only')
        # For strip-only treatments, get stripping operations
        stripping_operations = Operation.stripping_operations
        operations = operations.select { |op|
          criteria[:anodising_types].include?(op.process_type) || op.process_type == 'stripping'
        } + stripping_operations
      else
        operations = operations.select { |op| criteria[:anodising_types].include?(op.process_type) }
      end
    end

    # Exclude auto-inserted operations from manual selection
    operations = operations.reject { |op| op.auto_inserted? }

    # Filter by alloys (skip for stripping_only)
    if criteria[:alloys].present?
      operations = operations.select { |op|
        op.process_type == 'stripping' || (op.alloys & criteria[:alloys]).any?
      }
    end

    # Filter by anodic classes (skip for chromic anodising and stripping)
    if criteria[:anodic_classes].present?
      operations = operations.select { |op|
        if op.process_type == 'chromic_anodising' || op.process_type == 'stripping'
          true
        else
          (op.anodic_classes & criteria[:anodic_classes]).any?
        end
      }
    end

    # Filter by ENP types
    if criteria[:enp_types].present?
      operations = operations.select { |op| op.enp_type.present? && criteria[:enp_types].include?(op.enp_type) }
    end

    # Filter by target thickness (with tolerance) - skip for chromic anodising, stripping, and other non-thickness operations
    if criteria[:target_thicknesses].present?
      operations = operations.select do |op|
        if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'chromic_anodising', 'enp_heat_treatment', 'enp_post_heat_treatment', 'enp_baking', 'local_treatment', 'stripping'])
          true
        else
          criteria[:target_thicknesses].any? do |target|
            (op.target_thickness - target).abs <= 2.5
          end
        end
      end

      # Sort by closest thickness match
      if criteria[:target_thicknesses].length == 1
        target = criteria[:target_thicknesses].first
        operations = operations.sort_by do |op|
          if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'chromic_anodising', 'enp_heat_treatment', 'enp_post_heat_treatment', 'enp_baking', 'local_treatment', 'stripping'])
            0
          else
            (op.target_thickness - target).abs
          end
        end
      end
    end

    # Convert to JSON format
    results = operations.map do |op|
      {
        id: op.id,
        display_name: op.display_name,
        operation_text: op.operation_text,
        vat_options_text: op.vat_options_text,
        target_thickness: op.target_thickness,
        process_type: op.process_type,
        alloys: op.alloys,
        anodic_classes: op.anodic_classes,
        specifications: op.specifications,
        enp_type: op.enp_type,
        deposition_rate_range: op.deposition_rate_range,
        time: op.time
      }
    end

    render json: results
  end

  def operation_details
    operation_ids = params[:operation_ids] || []
    target_thickness = params[:target_thickness]&.to_f

    all_operations = Operation.all_operations(target_thickness)

    results = operation_ids.map do |op_id|
      operation = all_operations.find { |op| op.id == op_id }
      if operation
        {
          id: operation.id,
          display_name: operation.display_name,
          operation_text: operation.operation_text,
          vat_options_text: operation.vat_options_text,
          target_thickness: operation.target_thickness,
          process_type: operation.process_type,
          specifications: operation.specifications,
          enp_type: operation.enp_type,
          deposition_rate_range: operation.deposition_rate_range,
          time: operation.time
        }
      end
    end.compact

    render json: results
  end

  def preview_operations
    treatments_data = parse_treatments_param(params[:treatments_data])
    selected_alloy = params[:selected_alloy]
    selected_operations = parse_json_param(params[:selected_operations]) || []
    enp_strip_type = params[:enp_strip_type] || 'nitric'
    aerospace_defense = params[:aerospace_defense] || false
    selected_enp_pre_heat_treatment = params[:selected_enp_pre_heat_treatment]
    selected_enp_heat_treatment = params[:selected_enp_heat_treatment]

    # Get operations using the updated treatment cycle system - includes correct stripping sequence:
    # For anodising cycles: Degrease → Strip → DeOx → Main Operation
    # For strip-only: Degrease → Strip → DeOx
    # Also includes OCV, foil verification, water break, and ENP heat treatments

      Rails.logger.info "🔍 preview_operations aerospace_defense param: #{params[:aerospace_defense].inspect}"

    operations_with_auto_ops = Part.simulate_operations_with_auto_ops(
      treatments_data,
      nil,  # selected_jig_type no longer used globally
      selected_alloy,
      selected_operations,
      enp_strip_type,
      aerospace_defense, # This parameter enables water break, foil verification, and OCV insertion
      selected_enp_heat_treatment,
      selected_enp_pre_heat_treatment
    )

    render json: { operations: operations_with_auto_ops }
  end

  def insert_operation
    @part = Part.find(params[:id])

    position = params[:position]&.to_i
    operation_text = params[:operation_text]
    display_name = params[:display_name]

    @part.locked_operations.each do |op|
    end

    if position.nil? || operation_text.blank?
      render json: { success: false, error: 'Position and operation text are required' }, status: :unprocessable_entity
      return
    end

    if @part.insert_operation_at(position, operation_text, display_name)
      # Reload to get fresh data from database
      @part.reload

      @part.locked_operations.each do |op|
      end

      # Return the updated operations list for optimistic UI sync
      render json: {
        success: true,
        message: 'Operation inserted successfully',
        operations: @part.locked_operations.map { |op|
          {
            id: op["id"],
            display_name: op["display_name"],
            operation_text: op["operation_text"],
            position: op["position"],
            specifications: op["specifications"],
            vat_numbers: op["vat_numbers"] || [],
            process_type: op["process_type"],
            target_thickness: op["target_thickness"] || 0,
            auto_inserted: op["auto_inserted"] || false
          }
        }
      }
    else
      render json: {
        success: false,
        error: 'Failed to insert operation'
      }, status: :unprocessable_entity
    end
  rescue => e
    render json: {
      success: false,
      error: 'An error occurred while inserting the operation'
    }, status: :internal_server_error
  end

  def reorder_operation
    @part = Part.find(params[:id])

    from_position = params[:from_position]&.to_i
    to_position = params[:to_position]&.to_i

    if from_position.nil? || to_position.nil?
      render json: { success: false, error: 'Both from_position and to_position are required' }, status: :unprocessable_entity
      return
    end

    if @part.reorder_operation(from_position, to_position)
      render json: {
        success: true,
        message: 'Operation reordered successfully',
        operations: @part.locked_operations.map { |op|
          {
            id: op["id"],
            display_name: op["display_name"],
            operation_text: op["operation_text"],
            position: op["position"],
            specifications: op["specifications"],
            vat_numbers: op["vat_numbers"] || [],
            process_type: op["process_type"],
            target_thickness: op["target_thickness"] || 0,
            auto_inserted: op["auto_inserted"] || false
          }
        }
      }
    else
      render json: {
        success: false,
        error: 'Failed to reorder operation'
      }, status: :unprocessable_entity
    end
  rescue => e
    render json: {
      success: false,
      error: 'An error occurred while reordering the operation'
    }, status: :internal_server_error
  end

  def delete_operation
    @part = Part.find(params[:id])

    position = params[:position]&.to_i

    if position.nil?
      render json: { success: false, error: 'Position is required' }, status: :unprocessable_entity
      return
    end

    if @part.delete_operation_at(position)
      render json: {
        success: true,
        message: 'Operation deleted successfully',
        operations: @part.locked_operations.map { |op|
          {
            id: op["id"],
            display_name: op["display_name"],
            operation_text: op["operation_text"],
            position: op["position"],
            specifications: op["specifications"],
            vat_numbers: op["vat_numbers"] || [],
            process_type: op["process_type"],
            target_thickness: op["target_thickness"] || 0,
            auto_inserted: op["auto_inserted"] || false
          }
        }
      }
    else
      render json: {
        success: false,
        error: 'Failed to delete operation'
      }, status: :unprocessable_entity
    end
  rescue => e
    render json: {
      success: false,
      error: 'An error occurred while deleting the operation'
    }, status: :internal_server_error
  end

  # Search all parts across all customers (for copy functionality)
  def search_all_parts
    if params[:q].present?
      search_term = params[:q].upcase.strip
      @parts = Part.enabled
                  .includes(:customer)
                  .where(
                    "UPPER(part_number) ILIKE ? OR UPPER(description) ILIKE ?",
                    "%#{search_term}%", "%#{search_term}%"
                  )
                  .order(:part_number, :part_issue)
                  .limit(50) # Limit to prevent large result sets
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
            customer_id: part.customer_id,
            specification: part.specification,
            operations_summary: part.operations_summary,
            description: part.description
          }
        }
      end
    end
  end

  # Get operations from a part for copying
  def copy_operations
    @part = Part.find(params[:id])

    begin
      # Get operations from the source part
      operations = @part.get_operations_with_auto_ops

      if operations.empty?
        render json: {
          success: false,
          error: 'No operations found for this part'
        }
        return
      end

      # Format operations for the frontend - INCLUDING proper display names
      formatted_operations = operations.map.with_index do |operation, index|
        {
          id: operation.id,
          display_name: operation.display_name,  # This is the proper name like "Contract Review", "Standard Anodising", etc.
          operation_text: operation.operation_text,
          position: index + 1,
          specifications: operation.respond_to?(:specifications) ? (operation.specifications || '') : '',
          vat_numbers: operation.respond_to?(:vat_numbers) ? (operation.vat_numbers || []) : [],
          process_type: operation.respond_to?(:process_type) ? (operation.process_type || 'manual') : 'manual',
          target_thickness: operation.respond_to?(:target_thickness) ? (operation.target_thickness || 0) : 0,
          auto_inserted: operation.respond_to?(:auto_inserted?) ? operation.auto_inserted? : false
        }
      end

      render json: {
        success: true,
        operations: formatted_operations,
        source_part: @part.display_name,
        customer_name: @part.customer.name
      }
    rescue => e
      render json: {
        success: false,
        error: 'An error occurred while copying operations'
      }, status: :internal_server_error
    end
  end

  private

  def operation_params
    params.permit(:position, :operation_text, :display_name, :from_position, :to_position)
  end

  def set_part
    @part = Part.find(params[:id])
  end

  def part_params
    params.require(:part).permit(
      :customer_id, :part_number, :part_issue, :enabled,
      :special_instructions, :material, :specified_thicknesses,
      :process_type, :description, :each_price, :specification,
      customisation_data: {}
    )
  end

  def filter_params
    params.permit(
      anodising_types: [],
      alloys: [],
      target_thicknesses: [],
      anodic_classes: [],
      enp_types: []
    )
  end

  def load_form_data_for_errors
    @customers = Organization.enabled.order(:name)
    @specification_presets = SpecificationPreset.enabled.ordered
  end

  def determine_process_type
    treatments_json = part_params.dig(:customisation_data, "operation_selection", "treatments")
    return 'anodising' if treatments_json.blank?

    treatments = parse_json_param(treatments_json)
    return 'anodising' if treatments.empty?

    first_treatment = treatments.first
    treatment_type = first_treatment&.dig("type")

    # Map treatment types to process types
    case treatment_type
    when 'stripping_only'
      'stripping'
    when 'electroless_nickel_plating'
      'electroless_nickel_plating'
    when 'chemical_conversion'
      'chemical_conversion'
    else
      'anodising'
    end
  end

  def update_locked_operations_text
    return false unless @part.locked_for_editing?

    locked_operations_params = params[:locked_operations] || {}
    success = true

    locked_operations_params.each do |position, operation_text|
      result = @part.update_locked_operation!(position.to_i, operation_text)
      unless result
        success = false
      end
    end

    success
  end

  # Helper method to parse JSON parameters safely
  def parse_json_param(param)
    return [] if param.blank?
    return param if param.is_a?(Array) # Already parsed

    JSON.parse(param)
  rescue JSON::ParserError => e
    []
  end

  # Helper method specifically for treatments data
  def parse_treatments_param(param)
    return [] if param.blank?
    return param if param.is_a?(Array) # Already parsed

    JSON.parse(param)
  rescue JSON::ParserError => e
    []
  end
end
