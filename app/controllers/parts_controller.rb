class PartsController < ApplicationController
  before_action :set_part, only: [:show, :edit, :update, :destroy, :toggle_enabled, :lock_operations, :update_locked_operations]

  def index
    @parts = Part.includes(:customer, :works_orders)
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
    Rails.logger.info "🔍 Raw Params: #{params.inspect}"
    Rails.logger.info "🔍 Part Params: #{part_params.inspect}"
    Rails.logger.info "🔍 Switch to Manual: #{params[:switch_to_manual]}"

    @part = Part.new(part_params)

    Rails.logger.info "🔍 Part before save: customer_id=#{@part.customer_id}, part_number=#{@part.uniform_part_number}, part_issue=#{@part.uniform_part_issue}"

    # Set defaults for new parts with processing instructions
    @part.process_type = determine_process_type if @part.process_type.blank?

    # Handle manual mode switch - generate operations and lock them before save
    if params[:switch_to_manual] == 'true'
      Rails.logger.info "🔄 Processing manual mode switch for new part"

      begin
        # Generate operations from current configuration
        current_ops = @part.get_operations_with_auto_ops

        if current_ops.empty?
          Rails.logger.warn "⚠️ No operations generated for manual mode switch"
          @part.errors.add(:base, "No operations found to switch to manual mode. Please configure treatments first.")
          load_form_data_for_errors
          render :new, status: :unprocessable_entity
          return
        end

        # Lock the operations before saving
        @part.customisation_data = @part.customisation_data.dup || {}
        @part.customisation_data["operation_selection"] ||= {}
        @part.customisation_data["operation_selection"]["locked"] = true
        @part.customisation_data["operation_selection"]["locked_operations"] = current_ops.map.with_index do |op, index|
          {
            "id" => op.id,
            "display_name" => op.display_name,
            "operation_text" => op.operation_text,
            "position" => index + 1,
            "specifications" => op.specifications,
            "vat_numbers" => op.vat_numbers,
            "process_type" => op.process_type,
            "target_thickness" => op.target_thickness,
            "auto_inserted" => op.respond_to?(:auto_inserted?) ? op.auto_inserted? : false
          }
        end

        Rails.logger.info "🔒 Locked #{current_ops.length} operations for manual editing"

      rescue => e
        Rails.logger.error "❌ Error during manual mode switch: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
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
      Rails.logger.error "🚨 Part Save Errors: #{@part.errors.full_messages}"
      load_form_data_for_errors
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @customers = [@part.customer] # Don't allow changing customer on existing part
    @specification_presets = SpecificationPreset.enabled.ordered

    # Ensure customisation_data structure exists for unlocked parts
    if !@part.locked_for_editing?
      @part.customisation_data = { "operation_selection" => {} } if @part.customisation_data.blank?
    end
  end

  def update
    # Handle manual mode switch for existing parts
    if params[:switch_to_manual] == 'true'
      Rails.logger.info "🔄 Processing manual mode switch for existing part"

      begin
        # Generate operations from current configuration
        current_ops = @part.get_operations_with_auto_ops

        if current_ops.empty?
          Rails.logger.warn "⚠️ No operations generated for manual mode switch"
          redirect_to edit_part_path(@part), alert: 'No operations found to switch to manual mode. Please configure treatments first.'
          return
        end

        # Update with new data first, then lock operations
        if @part.update(part_params)
          # Now lock the operations
          @part.customisation_data = @part.customisation_data.dup || {}
          @part.customisation_data["operation_selection"] ||= {}
          @part.customisation_data["operation_selection"]["locked"] = true
          @part.customisation_data["operation_selection"]["locked_operations"] = current_ops.map.with_index do |op, index|
            {
              "id" => op.id,
              "display_name" => op.display_name,
              "operation_text" => op.operation_text,
              "position" => index + 1,
              "specifications" => op.specifications,
              "vat_numbers" => op.vat_numbers,
              "process_type" => op.process_type,
              "target_thickness" => op.target_thickness,
              "auto_inserted" => op.respond_to?(:auto_inserted?) ? op.auto_inserted? : false
            }
          end

          @part.save!
          Rails.logger.info "🔒 Locked #{current_ops.length} operations for manual editing"
          redirect_to edit_part_path(@part), notice: 'Part updated and switched to manual editing mode. You can now customize each operation.'
          return
        else
          @customers = [@part.customer]
          @specification_presets = SpecificationPreset.enabled.ordered
          render :edit, status: :unprocessable_entity
          return
        end

      rescue => e
        Rails.logger.error "❌ Error during manual mode switch: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        redirect_to edit_part_path(@part), alert: "Failed to switch to manual mode: #{e.message}"
        return
      end
    end

    # Handle locked operations update differently
    if @part.locked_for_editing? && params[:locked_operations].present?
      if update_locked_operations_text
        redirect_to @part, notice: 'Operations were successfully updated.'
      else
        @customers = [@part.customer]
        @specification_presets = SpecificationPreset.enabled.ordered
        render :edit, status: :unprocessable_entity
      end
      return
    end

    # For parts, changing customer/part_number/issue creates a new part
    if part_details_changed?
      new_part = Part.ensure(
        customer_id: part_params[:customer_id],
        part_number: part_params[:uniform_part_number],
        part_issue: part_params[:uniform_part_issue]
      )

      # Copy over the processing data to new part
      if new_part != @part
        new_part.update!(
          specification: part_params[:specification],
          special_instructions: part_params[:special_instructions],
          process_type: part_params[:process_type],
          customisation_data: part_params[:customisation_data] || {},
          enabled: part_params[:enabled]
        )
        redirect_to new_part, notice: 'Part details updated - redirected to the correct part record.'
        return
      end
    end

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

  def lock_operations
    if @part.locked_for_editing?
      redirect_to edit_part_path(@part), alert: 'Part operations are already locked.'
      return
    end

    # This method is now only for existing parts - new parts use the switch_to_manual approach
    if !@part.persisted?
      redirect_to edit_part_path(@part), alert: 'Cannot lock operations on unsaved parts. Use the manual mode switch instead.'
      return
    end

    begin
      @part.lock_operations!
      redirect_to edit_part_path(@part), notice: 'Operations locked for editing. You can now customize the operation text.'
    rescue => e
      Rails.logger.error "Error locking operations: #{e.message}"
      redirect_to edit_part_path(@part), alert: 'Failed to lock operations. Please ensure operations are configured first.'
    end
  end

  def update_locked_operations
    if update_locked_operations_text
      redirect_to @part, notice: 'Operations were successfully updated.'
    else
      redirect_to edit_part_path(@part), alert: 'Failed to update operations.'
    end
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

    Rails.logger.info "Preview params: treatments=#{treatments_data.length}, pre_heat_treatment=#{selected_enp_pre_heat_treatment}, post_heat_treatment=#{selected_enp_heat_treatment}, aerospace=#{aerospace_defense}"

    # Get operations using the treatment cycle system - includes OCV, foil verification, and strip-only support
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

    Rails.logger.info "Generated operations: #{operations_with_auto_ops.length} operations (includes water break, foil verification, OCV, and strip-only if aerospace_defense=#{aerospace_defense})"

    render json: { operations: operations_with_auto_ops }
  end

  private

  def set_part
    @part = Part.find(params[:id])
  end

  def part_params
    params.require(:part).permit(
      :customer_id, :uniform_part_number, :uniform_part_issue, :enabled,
      :specification, :special_instructions, :process_type,
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

  def part_details_changed?
    return false unless @part.persisted?

    params[:part][:uniform_part_number] != @part.uniform_part_number ||
    params[:part][:uniform_part_issue] != @part.uniform_part_issue ||
    params[:part][:customer_id] != @part.customer_id.to_s
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

    locked_operations_params.each do |operation_id, operation_text|
      unless @part.update_locked_operation!(operation_id, operation_text)
        success = false
        Rails.logger.error "Failed to update operation #{operation_id} with text: #{operation_text}"
      end
    end

    if success
      # Regenerate specification from updated operations
      @part.update!(specification: @part.operations_text)
    end

    success
  end

  # Helper method to parse JSON parameters safely
  def parse_json_param(param)
    return [] if param.blank?
    return param if param.is_a?(Array) # Already parsed

    JSON.parse(param)
  rescue JSON::ParserError => e
    Rails.logger.error "JSON Parse Error: #{e.message} for param: #{param}"
    []
  end

  # Helper method specifically for treatments data
  def parse_treatments_param(param)
    return [] if param.blank?
    return param if param.is_a?(Array) # Already parsed

    JSON.parse(param)
  rescue JSON::ParserError => e
    Rails.logger.error "Treatments JSON Parse Error: #{e.message} for param: #{param}"
    []
  end
end
