# app/operation_library/operations/inspect_final_inspect_vat_inspect.rb
module OperationLibrary
  class InspectFinalInspectVatInspect
    ANODIC_PROCESS_TYPES = %w[chromic hard sulphuric].freeze
    ENP_PROCESS_TYPES    = %w[enp].freeze

    def self.operations
      [
        # Initial incoming inspection - auto-inserted after contract review
        Operation.new(
          id: 'INCOMING_INSPECT',
          process_type: 'inspect',
          operation_text: '**Inspect** - Count quantity incoming against PO. Check for damage and/or contamination; if parts are non-conforming segregate (see IP2011). Check for Foreign Object Debris (FOD).'
        ),

        # VAT inspection - auto-inserted before degrease
        Operation.new(
          id: 'VAT_INSPECT',
          process_type: 'vat_inspect',
          operation_text: '**VAT Inspection** - Ensure all VAT solutions are visually free from contamination before use. Do not proceed, if contamination is visible and inform maintenance.'
        ),

        # Final inspection - auto-inserted before pack
        # NOTE: use get_final_inspection_operation(operations_sequence:, aerospace:) when
        # building a job card so the correct variant is selected. The static entry below
        # uses standard text and is retained only for reference/fallback purposes.
        Operation.new(
          id: 'FINAL_INSPECT',
          process_type: 'final_inspect',
          operation_text: final_inspect_text_standard
        )
      ]
    end

    # All inspections are always required for every job
    def self.incoming_inspection_required?(operations_sequence)
      !operations_sequence.empty?
    end

    def self.vat_inspection_required?(operations_sequence)
      !operations_sequence.empty?
    end

    def self.final_inspection_required?(operations_sequence)
      !operations_sequence.empty?
    end

    # Get specific inspection operations
    def self.get_incoming_inspection_operation
      operations.find { |op| op.id == 'INCOMING_INSPECT' }
    end

    def self.get_vat_inspection_operation
      operations.find { |op| op.id == 'VAT_INSPECT' }
    end

    # Returns the correct FINAL_INSPECT operation based on process types and aerospace flag.
    #
    # Variant selection:
    #   - Aerospace + any anodic (chromic/hard/sulphuric) → 8-reading anodic text
    #     (anodic takes precedence even when chromate conversion is also present)
    #   - Aerospace + ENP only (no anodic)               → 6-reading (a–f) ENP text
    #   - All other cases incl. aerospace + chromate only → standard text
    #
    # @param operations_sequence [Array<Operation>] the job's ordered operation list
    # @param aerospace [Boolean] whether the part is flagged aerospace/defence
    def self.get_final_inspection_operation(operations_sequence: [], aerospace: false)
      Operation.new(
        id: 'FINAL_INSPECT',
        process_type: 'final_inspect',
        operation_text: final_inspect_text(operations_sequence: operations_sequence, aerospace: aerospace)
      )
    end

    # -------------------------------------------------------------------------
    private
    # -------------------------------------------------------------------------

    def self.final_inspect_text(operations_sequence:, aerospace:)
      process_types = operations_sequence.map(&:process_type)

      if aerospace && process_types.any? { |pt| ANODIC_PROCESS_TYPES.include?(pt) }
        final_inspect_text_aerospace_anodic
      elsif aerospace && process_types.any? { |pt| ENP_PROCESS_TYPES.include?(pt) }
        final_inspect_text_aerospace_enp
      else
        final_inspect_text_standard
      end
    end

    def self.final_inspect_text_standard
      '**Final inspection** Check 100% of qty for uniform film appearance and film thickness, ' \
      'if qty wrong pls detail here ___ and inform an A stampholder, print out to be attached ' \
      'to release notes. **Check for Foreign Object Debris (FOD).**'
    end

    def self.final_inspect_text_aerospace_anodic
      '**Final inspection** Check 100% of qty for uniform film appearance. ' \
      'For every batch processed record 8 film thickness measurements minimum. ' \
      'It will not be possible to release the order without these readings. ' \
      'The CofC will render the minimum, maximum and mean of those readings.'
    end

    def self.final_inspect_text_aerospace_enp
      '**Final inspection** Check 100% of qty for uniform film appearance. ' \
      'For every batch processed record 6 film thickness measurements (a–f) minimum. ' \
      'It will not be possible to release the order without these readings. ' \
      'The CofC will render the minimum, maximum and mean of those readings.'
    end
  end
end
