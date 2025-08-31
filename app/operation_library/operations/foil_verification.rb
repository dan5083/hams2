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

    # Check if foil verification is required (aerospace/defense + anodising treatments)
    def self.foil_verification_required?(has_anodising_treatments, aerospace_defense: false)
      return false unless aerospace_defense
      has_anodising_treatments
    end

    # Get the foil verification operation
    def self.get_foil_verification_operation
      Operation.new(
        id: 'FOIL_VERIFICATION',
        process_type: 'verification',
        operation_text: build_foil_verification_text
      )
    end

    # Insert foil verification at the beginning of the sequence (after contract review)
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

    # Build the multi-batch foil verification text (matching OCV format exactly)
    def self.build_foil_verification_text
      batch_template = "Meter no:_ Foil value 1:___ Measured foil thickness:___ Foil value 2:___ Measured foil thickness:___"

      text_lines = []
      text_lines << "**Elcometer foil verification** (Aerospace/Defense requirement)"
      (1..3).each do |batch|
        text_lines << "Batch #{batch}: #{batch_template}"
      end

      text_lines.join("\n")
    end
  end
end
