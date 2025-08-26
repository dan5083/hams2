# app/operation_library/operations/ptfe.rb
module OperationLibrary
  class Ptfe
    def self.operations
      [
        # PTFE application operation
        Operation.new(
          id: 'PTFE_ANOLUBE',
          process_type: 'ptfe',
          operation_text: '**PTFE** - Anolube treatment 2-10 seconds, spray rinse white residue'
        )
      ]
    end

    # Get the PTFE operation
    def self.get_ptfe_operation
      operations.first
    end

    # Check if PTFE is applicable (only for anodising processes)
    def self.ptfe_applicable?(process_type)
      ['standard_anodising', 'hard_anodising', 'chromic_anodising'].include?(process_type)
    end
  end
end
