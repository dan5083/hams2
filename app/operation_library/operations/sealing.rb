# app/operation_library/operations/sealing.rb
module OperationLibrary
  class Sealing
    def self.operations
      [
        # Sodium Dichromate Sealing - high temperature process (extreme pH)
        Operation.new(
          id: 'SODIUM_DICHROMATE_SEAL',
          process_type: 'dichromate_sealing',
          operation_text: 'Seal in **Sodium Dichromate** at 93°C - 99°C for 2 minutes per micron (with a maximum of 25 minutes)'
        ),

        # Oxidite SE-CO Sealing - ambient temperature process
        Operation.new(
          id: 'OXIDITE_SECO_SEAL',
          process_type: 'sealing',
          operation_text: 'Seal in *Oxidite SE-CO* at 25 – 32°C for 1/2 - 1 minute per micron'
        ),

        # Hot Water Dip - quick process
        Operation.new(
          id: 'HOT_WATER_DIP',
          process_type: 'sealing',
          operation_text: '**Hot water dip 15-30 seconds'
        ),

        # Hot Seal - high temperature water sealing
        Operation.new(
          id: 'HOT_SEAL',
          process_type: 'sealing',
          operation_text: '**Seal in **hot seal** at 96°C for 1/2 min per micron'
        ),

        # SurTec 650V Sealing - mid temperature process
        Operation.new(
          id: 'SURTEC_650V_SEAL',
          process_type: 'sealing',
          operation_text: '*Surtec 650V* at 28-32°C for 1/2 - 1 minute per micron'
        ),

        # Laboratory Deionised Water Sealing
        Operation.new(
          id: 'DEIONISED_WATER_SEAL',
          process_type: 'sealing',
          operation_text: '(in works laboratory) Seal in deionised water at 75 to 85°C for 4-5 mins'
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

    # Get specific sealing operation by ID
    def self.get_sealing_operation(sealing_id)
      operations.find { |op| op.id == sealing_id }
    end
  end
end
