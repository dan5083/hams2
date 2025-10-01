# app/operation_library/operations/inspect_final_inspect_vat_inspect.rb
module OperationLibrary
  class InspectFinalInspectVatInspect
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
        Operation.new(
          id: 'FINAL_INSPECT',
          process_type: 'final_inspect',
          operation_text: '**Final inspection** - Check 100% of qty for uniform film appearance and film thickness, if qty wrong pls detail here ___ and inform an A stampholder, print out to be attached to release notes. **Check for Foreign Object Debris (FOD).'
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

    def self.get_final_inspection_operation
      operations.find { |op| op.id == 'FINAL_INSPECT' }
    end
  end
end
