# app/controllers/operations_controller.rb - Cleaned version
class OperationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:filter, :details, :preview_with_auto_ops]

  def filter
    criteria = filter_params

    # Extract thickness for ENP operations
    target_thickness = criteria[:target_thicknesses]&.first

    # Start with all operations - pass thickness to ENP operations
    operations = Operation.all_operations(target_thickness)

    # Filter by anodising types - exclude auto-inserted operations
    if criteria[:anodising_types].present?
      operations = operations.select { |op| criteria[:anodising_types].include?(op.process_type) }
    end

    # Exclude auto-inserted operations from manual selection
    operations = operations.reject { |op| op.auto_inserted? }

    # Filter by alloys
    if criteria[:alloys].present?
      operations = operations.select { |op| (op.alloys & criteria[:alloys]).any? }
    end

    # Filter by anodic classes
    if criteria[:anodic_classes].present?
      operations = operations.select { |op| (op.anodic_classes & criteria[:anodic_classes]).any? }
    end

    # Filter by ENP types
    if criteria[:enp_types].present?
      operations = operations.select { |op| op.enp_type.present? && criteria[:enp_types].include?(op.enp_type) }
    end

    # Filter by target thickness (with tolerance)
    if criteria[:target_thicknesses].present?
      operations = operations.select do |op|
        # Skip thickness filtering for chemical conversion, ENP
        if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating'])
          true
        else
          # Exact match or within reasonable tolerance (±2.5μm)
          criteria[:target_thicknesses].any? do |target|
            (op.target_thickness - target).abs <= 2.5
          end
        end
      end

      # Sort by closest thickness match (but only for anodising operations)
      if criteria[:target_thicknesses].length == 1
        target = criteria[:target_thicknesses].first
        operations = operations.sort_by do |op|
          if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating'])
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

  def details
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

  def preview_with_auto_ops
    treatments_data = params[:treatments_data] || []
    selected_jig_type = params[:selected_jig_type]
    selected_alloy = params[:selected_alloy]
    selected_operations = params[:selected_operations] || []
    enp_strip_type = params[:enp_strip_type] || 'nitric'
    aerospace_defense = params[:aerospace_defense] || false


    # Get operations using the treatment cycle system with ENP Strip/Mask data
    operations_with_auto_ops = PartProcessingInstruction.simulate_operations_with_auto_ops(
      treatments_data,
      selected_jig_type,
      selected_alloy,
      selected_operations,
      enp_strip_type
      aerospace_defense
    )

    render json: { operations: operations_with_auto_ops }
  end

  private

  def filter_params
    params.permit(
      anodising_types: [],
      alloys: [],
      target_thicknesses: [],
      anodic_classes: [],
      enp_types: []
    )
  end

  # Handle ENP Strip Mask operations
  def handle_enp_strip_mask_operations(selected_operations, enp_strip_type = 'nitric')
    enp_strip_mask_ids = [
      'ENP_MASK', 'ENP_MASKING_CHECK', 'ENP_STRIP_NITRIC',
      'ENP_STRIP_METEX', 'ENP_STRIP_MASKING', 'ENP_MASKING_CHECK_FINAL'
    ]

    # Check if any ENP Strip Mask operations are selected
    has_enp_strip_mask = selected_operations.any? { |op_id| enp_strip_mask_ids.include?(op_id) }
    return [] unless has_enp_strip_mask && defined?(OperationLibrary::EnpStripMask)

    # Get the appropriate ENP Strip Mask operations
    enp_operations = OperationLibrary::EnpStripMask.operations(enp_strip_type || 'nitric')

    enp_operations.map do |operation|
      {
        id: operation.id,
        display_name: operation.display_name,
        operation_text: operation.operation_text,
        auto_inserted: false # ENP Strip Mask are user-selected, not auto-inserted
      }
    end
  end
end
