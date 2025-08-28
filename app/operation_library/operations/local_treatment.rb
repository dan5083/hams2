# app/operation_library/operations/local_treatment.rb
module OperationLibrary
  class LocalTreatment
    def self.operations
      [
        # Local Alochrom 1200 application with pen
        Operation.new(
          id: 'LOCAL_ALOCHROM_1200_PEN',
          process_type: 'local_treatment',
          operation_text: 'Apply Alochrom 1200 locally using pen applicator as per drawing requirements',
          specifications: 'MIL-DTL-5541 Type I Class 1A and Class 3, Def Stan 03-18 Code C'
        ),

        # Local SurTec 650V application with pen
        Operation.new(
          id: 'LOCAL_SURTEC_650V_PEN',
          process_type: 'local_treatment',
          operation_text: 'Apply SurTec 650V locally using pen applicator as per drawing requirements',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)'
        ),

        # Local PTFE application
        Operation.new(
          id: 'LOCAL_PTFE_APPLICATION',
          process_type: 'local_treatment',
          operation_text: 'Apply PTFE locally as per drawing requirements'
        )
      ]
    end

    # Get available local treatments for dropdown selection
    def self.available_local_treatments
      [
        { value: 'none', label: 'No Local Treatment' },
        { value: 'LOCAL_ALOCHROM_1200_PEN', label: 'Alochrom 1200 (Pen)' },
        { value: 'LOCAL_SURTEC_650V_PEN', label: 'SurTec 650V (Pen)' },
        { value: 'LOCAL_PTFE_APPLICATION', label: 'PTFE Application' }
      ]
    end

    # Get specific local treatment operation by ID
    def self.get_local_treatment_operation(local_treatment_id)
      operations.find { |op| op.id == local_treatment_id }
    end

    # Check if local treatment is applicable (only for anodising processes)
    def self.local_treatment_applicable?(process_type)
      ['standard_anodising', 'hard_anodising', 'chromic_anodising'].include?(process_type)
    end

    # Check if local treatment is selected
    def self.local_treatment_selected?(local_treatment_id)
      local_treatment_id.present? && local_treatment_id != 'none'
    end
  end
end
