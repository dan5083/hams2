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

    # Foil verification is required only for aerospace/defense applications with anodising
    def self.foil_verification_required?(operations_sequence, aerospace_defense: false)
      return false unless aerospace_defense
      return false if operations_sequence.empty?

      # Check if any anodising operations are present in the sequence
      anodising_process_types = ['standard_anodising', 'hard_anodising', 'chromic_anodising']
      has_anodising = operations_sequence.any? { |op| anodising_process_types.include?(op.process_type) }
      has_anodising
    end

    # Get the foil verification operation
    def self.get_foil_verification_operation
      operations.first
    end

    # Insert foil verification at the beginning of the sequence (before degreasing)
    def self.insert_foil_verification_if_required(operations_sequence, aerospace_defense: false)
      return operations_sequence unless foil_verification_required?(operations_sequence, aerospace_defense: aerospace_defense)

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
      batch_template = "Meter no: ___ Foil value 1: ___ Measured foil thickness: ___ Foil value 2: ___ Measured foil thickness: ___"

      [
        "**Elcometer foil verification**",
        "",
        "Batch 1: #{batch_template}",
        "Batch 2: #{batch_template}",
        "Batch 3: #{batch_template}"
      ].join("\n")
    end
  end
end
