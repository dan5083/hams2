# app/operation_library/operations/enp_heat_treatments.rb
module OperationLibrary
  class EnpHeatTreatments
    def self.operations(aerospace_defense: false)
      base_operations = [
        # Low temperature heat treatments (120-150°C)
        {
          id: 'ENP_HEAT_TREAT_120_130C_2_3H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 120-130 °C for 2 to 3 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_120_130C_1_3H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 120-130 °C for 1 to 3 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_120_130C_1_6H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat 120-130°C for 1-6 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_125C_5C_2H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 125°C +/-5°C for 2 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_140C_10C_8H_MIN',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 140°C +/- 10°C for minimum 8 hours'
        },

        {
          id: 'ENP_POST_HEAT_TREAT_140C_24H',
          process_type: 'enp_post_heat_treatment',
          operation_text: 'Post heat treat at 140 +/- 10°C for 24 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_140_150C_1_2H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 140-150°C for 1-2 hours'
        },

        # Medium-low temperature heat treatments (177-204°C)
        {
          id: 'ENP_BAKE_177_204C_6H',
          process_type: 'enp_baking',
          operation_text: 'Bake parts at 177 to 204°C for 6h'
        },

        {
          id: 'ENP_HEAT_TREAT_180C_1H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 180 °C for 1 hour'
        },

        {
          id: 'ENP_HEAT_TREAT_190C_6H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 190 +/- 4°C for 6 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_190C_14_8H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 190 +/- 14°C for 8 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_200C_8H_MIN',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 200°C +/- 10°C for a minimum 8 hours'
        },

        {
          id: 'ENP_HEAT_TREAT_232C_1H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 232°C for 1 hour'
        },

        # High temperature heat treatments (343-550°C)
        {
          id: 'ENP_HEAT_TREAT_343C_1_5H_AIR_CIRCULATING',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat Treat at 343°c ±10°c for a Minimum of 1.5 Hours within 4 hours of plating in an air circulating oven (Atmospheric – Non Inert)'
        },

        {
          id: 'ENP_HEAT_TREAT_350C_1H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 350 °C for 1 hour'
        },

        {
          id: 'ENP_HEAT_TREAT_395_405C_1H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 395-405°C for 1 hour'
        },

        {
          id: 'ENP_HEAT_TREAT_550C_1H',
          process_type: 'enp_heat_treatment',
          operation_text: 'Heat treat at 550°C for 1 hour'
        }
      ]

      # Map to Operation objects with conditional OCV
      base_operations.map do |op_data|
        operation_text = op_data[:operation_text]

        # Append OCV monitoring for aerospace/defense
        if aerospace_defense
          ocv_text = build_time_temp_monitoring_text
          operation_text += "\n\n**OCV Monitoring:**\n#{ocv_text}"
        end

        Operation.new(
          id: op_data[:id],
          process_type: op_data[:process_type],
          operation_text: operation_text
        )
      end
    end

    # Get available heat treatments for dropdown selection
    def self.available_heat_treatments
      operations.map { |op|
        {
          value: op.id,
          label: op.operation_text.gsub('Heat treat at ', '').gsub('Heat Treat at ', '').gsub('Bake parts at ', '').gsub('Post heat treat at ', 'Post: ')
        }
      }
    end

    # Get specific heat treatment operation by ID
    def self.get_heat_treatment_operation(heat_treatment_id, aerospace_defense: false)
      operations(aerospace_defense: aerospace_defense).find { |op| op.id == heat_treatment_id }
    end

    # Check if ENP heat treatment is selected
    def self.heat_treatment_selected?(heat_treatment_id)
      heat_treatment_id.present? && heat_treatment_id != 'none'
    end

    # Insert heat treatment after unjig but before ENP strip/mask operations
    # This is independent of strip/mask selection
    def self.insert_heat_treatment_if_required(operations_sequence, selected_heat_treatment_id, aerospace_defense: false)
      return operations_sequence unless heat_treatment_selected?(selected_heat_treatment_id)

      heat_treatment = get_heat_treatment_operation(selected_heat_treatment_id, aerospace_defense: aerospace_defense)
      return operations_sequence unless heat_treatment

      # Find unjig operation in the sequence
      unjig_index = operations_sequence.find_index { |op| op.process_type == 'unjig' }
      return operations_sequence unless unjig_index

      # Insert heat treatment after unjig (before any ENP strip/mask operations)
      operations_sequence.dup.tap do |seq|
        seq.insert(unjig_index + 1, heat_treatment)
      end
    end

    # Check if heat treatment is applicable (only for ENP processes)
    def self.heat_treatment_applicable?(treatments_data)
      return false unless treatments_data.present?

      treatments_data.any? { |treatment| treatment["type"] == "electroless_nickel_plating" }
    end

    # Build time/temp monitoring text (no voltage for heat treatments)
    def self.build_time_temp_monitoring_text
      text_lines = []
      (1..3).each do |batch|
        text_lines << "Batch ___: Time ___m ___s    Temp ___°C"
      end
      text_lines.join("\n")
    end
  end
end
