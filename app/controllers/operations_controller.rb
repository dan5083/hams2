# app/controllers/operations_controller.rb - Enhanced for masking removal operations
class OperationsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:filter, :details, :summary, :preview_with_auto_ops]

  def filter
    criteria = filter_params

    # Extract thickness for ENP operations
    target_thickness = criteria[:target_thicknesses]&.first

    # Start with all operations - pass thickness to ENP operations
    operations = Operation.all_operations(target_thickness)

    # Add masking operations (including removal operations)
    operations += OperationLibrary::Masking.operations

    # Add stripping operations
    operations << OperationLibrary::Stripping.get_stripping_operation(nil, nil)

    # Filter by anodising types (now includes ENP, ENP Strip Mask, masking, and stripping) - exclude auto-inserted operations
    if criteria[:anodising_types].present?
      operations = operations.select { |op| criteria[:anodising_types].include?(op.process_type) }
    end

    # Exclude auto-inserted operations (degrease, rinse, masking removal) from manual selection
    operations = operations.reject { |op| op.auto_inserted? }

    # Filter by alloys (not applicable to masking/stripping)
    if criteria[:alloys].present?
      operations = operations.select { |op|
        op.process_type.in?(['masking', 'stripping']) || (op.alloys & criteria[:alloys]).any?
      }
    end

    # Filter by anodic classes (not applicable to masking/stripping)
    if criteria[:anodic_classes].present?
      operations = operations.select { |op|
        op.process_type.in?(['masking', 'stripping']) || (op.anodic_classes & criteria[:anodic_classes]).any?
      }
    end

    # Filter by ENP types (not applicable to masking/stripping)
    if criteria[:enp_types].present?
      operations = operations.select { |op|
        op.process_type.in?(['masking', 'stripping']) || (op.enp_type.present? && criteria[:enp_types].include?(op.enp_type))
      }
    end

    # Filter by target thickness (with tolerance) - skip for chemical conversion, ENP, masking, and stripping
    if criteria[:target_thicknesses].present?
      operations = operations.select do |op|
        # Skip thickness filtering for chemical conversion, ENP, masking, stripping, and ENP Strip Mask
        if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'masking', 'stripping']) ||
           ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type)
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
          if op.process_type.in?(['chemical_conversion', 'electroless_nickel_plating', 'masking', 'stripping']) ||
             ['mask', 'masking_check', 'strip', 'strip_masking'].include?(op.process_type)
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
        operation_text: op.operation_text, # Now includes interpolated time for ENP and text for masking/stripping
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

    # DEBUG: Log operations with interpolated text
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
    enp_strip_type = params[:enp_strip_type] || 'nitric'
    masking_methods = params[:masking_methods] || {}
    stripping_type = params[:stripping_type]
    stripping_method = params[:stripping_method]

    # Handle ENP Strip Mask operations with correct strip type
    expanded_operation_ids = expand_enp_strip_mask_operations(operation_ids, enp_strip_type)

    all_operations = Operation.all_operations(target_thickness)

    # Add ENP Strip Mask operations with correct strip type
    enp_strip_operations = get_enp_strip_mask_operations(enp_strip_type)
    all_operations += enp_strip_operations

    # Add masking operations (including removal operations) with interpolation
    masking_ops = OperationLibrary::Masking.operations(masking_methods)
    all_operations += masking_ops

    # Add stripping operations with interpolation
    stripping_op = OperationLibrary::Stripping.get_stripping_operation(stripping_type, stripping_method)
    all_operations += [stripping_op]

    results = expanded_operation_ids.map do |op_id|
      operation = all_operations.find { |op| op.id == op_id }
      if operation
        {
          id: operation.id,
          display_name: operation.display_name,
          operation_text: operation.operation_text, # Includes interpolated time if ENP, or interpolated text for masking/stripping
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

  def summary
    operation_ids = params[:operation_ids] || []
    target_thickness = params[:target_thickness]&.to_f
    selected_jig_type = params[:selected_jig_type]
    enp_strip_type = params[:enp_strip_type] || 'nitric'
    masking_methods = params[:masking_methods] || {}
    stripping_type = params[:stripping_type]
    stripping_method = params[:stripping_method]

    # Handle ENP Strip Mask operations
    expanded_operation_ids = expand_enp_strip_mask_operations(operation_ids, enp_strip_type)

    # Pass all parameters for complete operation simulation
    summary = PartProcessingInstruction.simulate_operations_summary(
      expanded_operation_ids,
      target_thickness,
      selected_jig_type,
      enp_strip_type,
      masking_methods,
      stripping_type,
      stripping_method
    )
    render json: { summary: summary }
  end

  def preview_with_auto_ops
    operation_ids = params[:operation_ids] || []
    target_thickness = params[:target_thickness]&.to_f
    selected_jig_type = params[:selected_jig_type]
    enp_strip_type = params[:enp_strip_type] || 'nitric'
    masking_methods = params[:masking_methods] || {}
    stripping_type = params[:stripping_type]
    stripping_method = params[:stripping_method]

    # Handle ENP Strip Mask operations
    expanded_operation_ids = expand_enp_strip_mask_operations(operation_ids, enp_strip_type)

    # Pass all parameters including masking and stripping for complete operation simulation
    operations_with_auto_ops = PartProcessingInstruction.simulate_operations_with_auto_ops(
      expanded_operation_ids,
      target_thickness,
      selected_jig_type,
      enp_strip_type,
      masking_methods,
      stripping_type,
      stripping_method
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
      enp_types: [],
      masking_methods: {},
      stripping_type: {},
      stripping_method: {}
    )
  end

  # Expand ENP Strip Mask operation IDs to include all 5 operations
  def expand_enp_strip_mask_operations(operation_ids, enp_strip_type)
    expanded_ids = []

    operation_ids.each do |op_id|
      if enp_strip_mask_operation?(op_id)
        # Replace any ENP Strip Mask operation with the complete sequence
        unless expanded_ids.any? { |id| enp_strip_mask_operation?(id) }
          expanded_ids += get_enp_strip_mask_operation_ids(enp_strip_type)
        end
      else
        expanded_ids << op_id
      end
    end

    expanded_ids
  end

  # Check if operation ID is part of ENP Strip Mask sequence
  def enp_strip_mask_operation?(operation_id)
    enp_strip_mask_ids = [
      'ENP_MASK',
      'ENP_MASKING_CHECK',
      'ENP_STRIP_NITRIC',
      'ENP_STRIP_METEX',
      'ENP_STRIP_MASKING',
      'ENP_MASKING_CHECK_FINAL'
    ]
    enp_strip_mask_ids.include?(operation_id)
  end

  # Get ENP Strip Mask operation IDs for given strip type
  def get_enp_strip_mask_operation_ids(strip_type)
    if defined?(OperationLibrary::EnpStripMask)
      OperationLibrary::EnpStripMask.get_operation_ids(strip_type)
    else
      []
    end
  end

  # Get ENP Strip Mask operations for given strip type
  def get_enp_strip_mask_operations(strip_type)
    if defined?(OperationLibrary::EnpStripMask)
      OperationLibrary::EnpStripMask.operations(strip_type)
    else
      []
    end
  end
end
