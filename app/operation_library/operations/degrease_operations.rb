# app/operation_library/operations/degrease_operations.rb
module OperationLibrary
  class DegreaseOperations
    def self.operations
      [
        # Universal degreasing operation for all materials and processes
        Operation.new(
          id: 'OXIDITE_C8_DEGREASE',
          process_type: 'degrease',
          operation_text: 'Clean in Oxidite C-8 at 65-70°C for 5-10 mins',
          time: 7
        )
      ]
    end

    # Check if degreasing is required based on operation type AND alloy
    def self.degreasing_required?(operation, selected_alloy = nil)
      # ENP requires degrease only for aluminium-based alloys
      if operation.process_type == 'electroless_nickel_plating'
        return aluminium_based_alloy?(selected_alloy)
      end

      # All other surface treatments require degrease
      surface_treatment_processes = %w[
        standard_anodising
        hard_anodising
        chromic_anodising
        chemical_conversion
        stripping_only
      ]

      surface_treatment_processes.include?(operation.process_type)
    end

    # Check if alloy is aluminium-based (requires degrease for ENP)
    def self.aluminium_based_alloy?(alloy)
      return false if alloy.blank?

      aluminium_alloys = [
        'ALUMINIUM',
        'TWO_THOUSAND_SERIES_ALLOYS',
        'COPE_ROLLED_ALUMINIUM',
        'MCLAREN_STA142_PROCEDURE_D'
      ]

      aluminium_alloys.include?(alloy.upcase)
    end

    # Get the degreasing operation
    def self.get_degrease_operation
      operations.first
    end
  end
end
