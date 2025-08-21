# app/controllers/operations_controller.rb
class OperationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:filter, :details]

  def filter
    criteria = filter_params

    # Start with all operations
    operations = Operation.all_operations

    # Filter by anodising types (now includes chemical_conversion)
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

    # Filter by target thickness (with tolerance) - skip for chemical conversion
    if criteria[:target_thicknesses].present?
      operations = operations.select do |op|
        # Skip thickness filtering for chemical conversion
        if op.process_type == 'chemical_conversion'
          true
        else
          criteria[:target_thicknesses].any? do |target|
            (op.target_thickness - target).abs <= 2.5
          end
        end
      end

      # Sort by closest thickness match (but only for non-chemical conversion)
      if criteria[:target_thicknesses].length == 1
        target = criteria[:target_thicknesses].first
        operations = operations.sort_by do |op|
          op.process_type == 'chemical_conversion' ? 0 : (op.target_thickness - target).abs
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
        specifications: op.specifications
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
          specifications: operation.specifications
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

  private

  def filter_params
    params.permit(
      anodising_types: [],
      alloys: [],
      target_thicknesses: [],
      anodic_classes: []
    )
  end
end
