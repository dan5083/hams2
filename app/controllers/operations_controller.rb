# app/controllers/operations_controller.rb - Enhanced for ENP support
class OperationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:filter, :details, :summary, :preview_with_rinses, :calculate_enp_time]

  def filter
    criteria = filter_params

    # Start with all operations
    operations = Operation.all_operations

    # Filter by anodising types (now includes ENP)
    if criteria[:anodising_types].present?
      operations = operations.select { |op| criteria[:anodising_types].include?(op.process_type) }
    end

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
      operations = operations.select { |op| criteria[:enp_types].include?(op.enp_type) }
    end

    # Filter by target thickness (with tolerance) - skip for chemical conversion and ENP
    if criteria[:target_thicknesses].present?
      operations = operations.select do |op|
        # Skip thickness filtering for chemical conversion and ENP
        if op.process_type == 'chemical_conversion' || op.process_type == 'electroless_nickel_plating'
          true
        else
          criteria[:target_thicknesses].any? do |target|
            (op.target_thickness - target).abs <= 2.5
          end
        end
      end

      # Sort by closest thickness match (but only for anodising operations)
      if criteria[:target_thicknesses].length == 1
        target = criteria[:target_thicknesses].first
        operations = operations.sort_by do |op|
          if op.process_type == 'chemical_conversion' || op.process_type == 'electroless_nickel_plating'
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
        deposition_rate_range: op.deposition_rate_range
      }
    end

    render json: results
  end

  def details
    operation_ids = params[:operation_ids] || []

    all_operations = Operation.all_operations

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
          deposition_rate_range: operation.deposition_rate_range
        }
      end
    end.compact

    render json: results
  end

  def summary
    operation_ids = params[:operation_ids] || []
    summary = PartProcessingInstruction.simulate_operations_summary(operation_ids)
    render json: { summary: summary }
  end

  # NEW: Preview operations with auto-inserted operations for form display
  def preview_with_auto_ops
    operation_ids = params[:operation_ids] || []
    operations_with_auto_ops = PartProcessingInstruction.simulate_operations_with_auto_ops(operation_ids)
    render json: { operations: operations_with_auto_ops }
  end

  # NEW: Calculate ENP plating time
  def calculate_enp_time
    operation_id = params[:operation_id]
    target_thickness = params[:target_thickness]&.to_f

    if operation_id.blank? || target_thickness.blank? || target_thickness <= 0
      render json: { error: 'Invalid parameters' }, status: 400
      return
    end

    operation = Operation.all_operations.find { |op| op.id == operation_id }

    if operation.nil? || !operation.electroless_nickel_plating?
      render json: { error: 'Operation not found or not ENP' }, status: 404
      return
    end

    time_data = operation.calculate_plating_time(target_thickness)

    if time_data
      render json: {
        operation_id: operation_id,
        target_thickness: target_thickness,
        time_estimate: time_data
      }
    else
      render json: { error: 'Unable to calculate plating time' }, status: 500
    end
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
end
