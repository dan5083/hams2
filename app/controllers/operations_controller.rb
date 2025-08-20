# app/controllers/operations_controller.rb
class OperationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:filter, :details]

  def filter
    criteria = filter_params

    # Start with all operations
    operations = Operation.all_operations

    # Filter by anodising types
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

    # Filter by target thickness (with tolerance)
    if criteria[:target_thicknesses].present?
      operations = operations.select do |op|
        criteria[:target_thicknesses].any? do |target|
          (op.target_thickness - target).abs <= 2.5
        end
      end

      # Sort by closest thickness match
      if criteria[:target_thicknesses].length == 1
        target = criteria[:target_thicknesses].first
        operations = operations.sort_by { |op| (op.target_thickness - target).abs }
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
        anodic_classes: op.anodic_classes
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
          process_type: operation.process_type
        }
      end
    end.compact

    render json: results
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
