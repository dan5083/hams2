# app/controllers/operations_controller.rb - Enhanced for ENP thickness interpolation
class OperationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:filter, :details, :summary, :preview_with_rinses]

  def filter
    criteria = filter_params

    # Extract thickness for ENP operations
    target_thickness = criteria[:target_thicknesses]&.first

    # Start with all operations - pass thickness to ENP operations
    operations = Operation.all_operations(target_thickness)

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
      operations = operations.select { |op| op.enp_type.present? && criteria[:enp_types].include?(op.enp_type) }
    end

    # Filter by target thickness (with tolerance) - skip for chemical conversion and ENP
    if criteria[:target_thicknesses].present?
      operations = operations.select do |op|
        # Skip thickness filtering for chemical conversion and ENP (already handled above)
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
        operation_text: op.operation_text, # Now includes interpolated time for ENP
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

    # DEBUG: Log ENP operations with interpolated text
    if criteria[:anodising_types]&.include?('electroless_nickel_plating')
      Rails.logger.info "🔍 ENP FILTER DEBUG:"
      Rails.logger.info "  - Thickness: #{target_thickness}μm"
      Rails.logger.info "  - Found #{results.length} operations"
      results.each do |result|
        Rails.logger.info "  - #{result[:id]}: #{result[:operation_text][0..80]}..."
      end
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
          operation_text: operation.operation_text, # Includes interpolated time if ENP
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
    target_thickness = params[:target_thickness]&.to_f

    # Pass thickness for ENP operation text interpolation
    summary = PartProcessingInstruction.simulate_operations_summary(operation_ids, target_thickness)
    render json: { summary: summary }
  end

  def preview_with_auto_ops
    operation_ids = params[:operation_ids] || []
    target_thickness = params[:target_thickness]&.to_f

    # Pass thickness for ENP operation text interpolation
    operations_with_auto_ops = PartProcessingInstruction.simulate_operations_with_auto_ops(operation_ids, target_thickness)
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
end
