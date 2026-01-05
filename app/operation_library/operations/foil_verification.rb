# app/operation_library/operations/foil_verification.rb
module OperationLibrary
  class FoilVerification
    def self.operations
      [
        Operation.new(
          id: 'FOIL_VERIFICATION',
          process_type: 'verification',
          operation_text: operation_text
        )
      ]
    end

    # Check if foil verification is required for a specific treatment (aerospace/defense + anodising)
    def self.foil_verification_required_for_treatment?(treatment_type, aerospace_defense: false)
      return false unless aerospace_defense
      anodising_treatments = ['standard_anodising', 'hard_anodising', 'chromic_anodising']
      anodising_treatments.include?(treatment_type)
    end

    # Get a foil verification operation for a specific treatment
    def self.get_foil_verification_operation_for_treatment(treatment_type, treatment_index = nil)
      Operation.new(
        id: "FOIL_VERIFICATION_#{treatment_type.upcase}#{treatment_index ? "_#{treatment_index}" : ""}",
        process_type: 'verification',
        operation_text: operation_text
      )
    end

    # Insert foil verification for a specific treatment at the beginning of that treatment cycle
    def self.insert_foil_verification_for_treatment(operations_sequence, treatment_type, treatment_index = nil, aerospace_defense: false)
      return operations_sequence unless foil_verification_required_for_treatment?(treatment_type, aerospace_defense: aerospace_defense)

      # Get the treatment-specific foil verification operation
      foil_verification_op = get_foil_verification_operation_for_treatment(treatment_type, treatment_index)

      # Insert at the beginning of the operations sequence (this will be called per-treatment)
      [foil_verification_op] + operations_sequence
    end

    private

    # Standard foil verification operation text
    def self.operation_text
      "**Elcometer foil verification** (Aerospace/Defense requirement)

    Batch 1: Meter no:___ Foil value 1:___ Measured foil thickness:___ Foil value 2:___ Measured foil thickness:___
    Batch 2: Meter no:___ Foil value 1:___ Measured foil thickness:___ Foil value 2:___ Measured foil thickness:___
    Batch 3: Meter no:___ Foil value 1:___ Measured foil thickness:___ Foil value 2:___ Measured foil thickness:___"
    end
  end
end
