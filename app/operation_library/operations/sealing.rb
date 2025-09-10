# app/operation_library/operations/sealing.rb
module OperationLibrary
  class Sealing
    def self.operations(aerospace_defense: false)
      [
        # Sodium Dichromate Sealing - high temperature process (extreme pH)
        Operation.new(
          id: 'SODIUM_DICHROMATE_SEAL',
          process_type: 'dichromate_sealing',
          operation_text: build_operation_text(
            'Seal in sodium dichromate at 93°C - 99°C for 2-3 minutes per μm of Measured Film Thickness (with a maximum of 30 minutes)',
            aerospace_defense
          )
        ),

        # Oxidite SE-CO Sealing - ambient temperature process
        Operation.new(
          id: 'OXIDITE_SECO_SEAL',
          process_type: 'sealing',
          operation_text: build_operation_text(
            'Seal in Oxidite SE-CO at 25-32°C for 0.5-1 minute per μm of Measured Film Thickness (with a maximum of 20 minutes)',
            aerospace_defense
          )
        ),

        # Hot Water Dip - quick process
        Operation.new(
          id: 'HOT_WATER_DIP',
          process_type: 'sealing',
          operation_text: build_operation_text(
            'Hot water dip for 15-30 seconds.',
            aerospace_defense
          )
        ),

        # Hot Seal - high temperature water sealing
        Operation.new(
          id: 'HOT_SEAL',
          process_type: 'sealing',
          operation_text: build_operation_text(
            'Seal in hot seal at 96°C for 2-3 minutes per μm of Measured Film Thickness (with a minimum of 10 mins, and a maximum of 40 mins)',
            aerospace_defense
          )
        ),

        # SurTec 650V Sealing - mid temperature process
        Operation.new(
          id: 'SURTEC_650V_SEAL',
          process_type: 'sealing',
          operation_text: build_operation_text(
            'Seal in SurTec 650V at 28-32°C for 0.5-1 minute per μm of Measured Film Thickness (with a maximum of 20 minutes)',
            aerospace_defense
          )
        ),

        # Laboratory Deionised Water Sealing
        Operation.new(
          id: 'DEIONISED_WATER_SEAL',
          process_type: 'sealing',
          operation_text: build_operation_text(
            'Seal in deionised water at 75-85°C for 4-5 minutes per μm of Measured Film Thickness (in works laboratory)',
            aerospace_defense
          )
        )
      ]
    end

    # Get available sealing types for form selection
    def self.available_sealing_types
      [
        { value: 'SODIUM_DICHROMATE_SEAL', label: 'Sodium Dichromate Seal' },
        { value: 'OXIDITE_SECO_SEAL', label: 'Oxidite SE-CO Seal' },
        { value: 'HOT_WATER_DIP', label: 'Hot Water Dip' },
        { value: 'HOT_SEAL', label: 'Hot Seal' },
        { value: 'SURTEC_650V_SEAL', label: 'SurTec 650V Seal' },
        { value: 'DEIONISED_WATER_SEAL', label: 'Deionised Water Seal' }
      ]
    end

    # Get specific sealing operation by ID with aerospace flag
    def self.get_sealing_operation(sealing_id, aerospace_defense: false)
      operations(aerospace_defense: aerospace_defense).find { |op| op.id == sealing_id }
    end

    private

    # Build operation text with optional aerospace calculation prompt
    def self.build_operation_text(base_text, aerospace_defense)
      if aerospace_defense
        "#{base_text}. Please calculate time range and record: _____m to _____m"
      else
        base_text
      end
    end
  end
end
