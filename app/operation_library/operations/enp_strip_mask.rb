# app/operation_library/operations/enp_strip_mask.rb
module OperationLibrary
  class EnpStripMask
    # Strip types available
    STRIP_TYPES = ['nitric', 'metex_dekote'].freeze

    def self.operations(strip_type = 'nitric')
      strip_operation = case strip_type.to_s.downcase
      when 'metex_dekote'
        metex_strip_operation
      else
        nitric_strip_operation
      end

      [
        # 1. Mask operation
        Operation.new(
          id: 'ENP_MASK',
          process_type: 'mask',
          operation_text: "Mask with 45 STOPPING OFF red dyed rubber-type lacquer.\n\n" +
                         "Note: masking in drawings oftentimes refers to masking from the plating process, " +
                         "which is practically impossible - we mask for the stripping process - so we leave " +
                         "areas indicated for masking bare nickel and mask all other areas.\n\n" +
                         "Clean up masking (done by same operator)"
        ),

        # 2. Masking check
        Operation.new(
          id: 'ENP_MASKING_CHECK',
          process_type: 'masking_check',
          operation_text: "Masking check (carried out by an independent operator to the previous OP), " +
                         "refer to drawing and note in the previous OP\n\n" +
                         "Check all masking boundaries for line integrity\n\n" +
                         "Check all non-masked areas for masking smudges and spatter"
        ),

        # 3. Strip operation (variable based on type)
        strip_operation,

        # 4. Strip masking
        Operation.new(
          id: 'ENP_STRIP_MASKING',
          process_type: 'strip_masking',
          operation_text: "Strip masking by peeling and MEK"
        ),

        # 5. Final masking and foreign body check
        Operation.new(
          id: 'ENP_MASKING_CHECK_FINAL',
          process_type: 'masking_check',
          operation_text: "Masking, and foreign body check (done by independent operator)"
        )
      ]
    end

    # Available strip types for dropdown/selection
    def self.available_strip_types
      [
        { value: 'nitric', label: 'Nitric Acid (Standard)' },
        { value: 'metex_dekote', label: 'Metex Dekote (Ferrous)' }
      ]
    end

    # Check if ENP strip mask sequence is needed  (when ENP operations are present)
    def self.enp_strip_mask_available?(selected_operations)
      return false if selected_operations.blank?

      # Check if any ENP operations are selected
      enp_operation_ids = [
        'HIGH_PHOS_VANDALLOY_4100',
        'MEDIUM_PHOS_NICKLAD_767',
        'LOW_PHOS_NICKLAD_ELV_824',
        'PTFE_NICKLAD_ICE'
      ]

      selected_operations.any? { |op_id| enp_operation_ids.include?(op_id) }
    end

    # Get all 5 operations for a given strip type
    def self.get_complete_sequence(strip_type = 'nitric')
      operations(strip_type)
    end

    # Get operation IDs for the complete sequence
    def self.get_operation_ids(strip_type = 'nitric')
      operations(strip_type).map(&:id)
    end

    private

    def self.nitric_strip_operation
      Operation.new(
        id: 'ENP_STRIP_NITRIC',
        process_type: 'strip',
        operation_text: "Strip nickel plating nitric acid solution 30 to 40 minutes per 25 microns " +
                       "[or until black smut dissolves]"
      )
    end

    def self.metex_strip_operation
      Operation.new(
        id: 'ENP_STRIP_METEX',
        process_type: 'strip',
        operation_text: "Strip ENP in Metex Dekote at 80 to 90C, " +
                       "for approximately 20 microns per hour strip rate."
      )
    end
  end
end
