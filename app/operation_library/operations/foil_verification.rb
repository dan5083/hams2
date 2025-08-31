# app/operation_library/operations/foil_verification.rb
module OperationLibrary
  class FoilVerification
    def self.operations
      [
        # Foil verification operation for aerospace/defense applications
        Operation.new(
          id: 'FOIL_VERIFICATION',
          process_type: 'verification',
          operation_text: build_foil_verification_text
        )
      ]
    end

    # FIXED: Check for anodising treatments, not operations in sequence
    def self.foil_verification_required?(has_anodising_treatments, aerospace_defense: false)
      return false unless aerospace_defense
      has_anodising_treatments
    end

    # Get the foil verification operation
    def self.get_foil_verification_operation
      operations.first
    end

    # FIXED: Take has_anodising parameter instead of checking sequence
    def self.insert_foil_verification_if_required(operations_sequence, has_anodising_treatments: false, aerospace_defense: false)
      return operations_sequence unless foil_verification_required?(has_anodising_treatments, aerospace_defense: aerospace_defense)

      # Check if foil verification is already present
      has_foil_verification = operations_sequence.any? { |op| op.process_type == 'verification' }
      return operations_sequence if has_foil_verification

      # Insert foil verification at the very beginning (after contract review but before any other operations)
      contract_review_index = operations_sequence.find_index { |op| op.process_type == 'contract_review' }

      if contract_review_index
        # Insert after contract review
        operations_sequence.dup.tap do |seq|
          seq.insert(contract_review_index + 1, get_foil_verification_operation)
        end
      else
        # Insert at the very beginning if no contract review found
        [get_foil_verification_operation] + operations_sequence
      end
    end

    private

    # Build the multi-batch foil verification text
    def self.build_foil_verification_text
      [
        "**Elcometer foil verification** (Aerospace/Defense requirement)",
        "Batch 1: Meter no:_ Foil value 1:___ Measured foil thickness:___ Foil value 2:___ Measured foil thickness:___",
        "Batch 2: Meter no:_ Foil value 1:___ Measured foil thickness:___ Foil value 2:___ Measured foil thickness:___",
        "Batch 3: Meter no:_ Foil value 1:___ Measured foil thickness:___ Foil value 2:___ Measured foil thickness:___"
      ].join("\n")
    end
  end
end
