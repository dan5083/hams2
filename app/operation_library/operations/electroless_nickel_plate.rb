# app/operation_library/operations/electroless_nickel_plate.rb
module OperationLibrary
  class ElectrolessNickelPlate
    def self.operations(target_thickness_um = nil, aerospace_defense: false)
      base_operations = [
        # High Phosphorous - Vandalloy 4100
        {
          id: 'HIGH_PHOS_VANDALLOY_4100',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cope_rolled_aluminium', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'high_phosphorous',
          target_thickness: nil,
          deposition_rate_range: [12.0, 14.1],
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Vandalloy 4100 (High Phos) at 82-91°C. Deposition rate: 12.0-14.1 μm/hour. Time for {THICKNESS}μm: {TIME_RANGE}"
        },

        # Medium Phosphorous - Nicklad 767
        {
          id: 'MEDIUM_PHOS_NICKLAD_767',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cope_rolled_aluminium', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'medium_phosphorous',
          target_thickness: nil,
          deposition_rate_range: [18.0, 23.0],
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Nicklad 767 (Medium Phos) at 82-91°C. Deposition rate: 18.0-23.0 μm/hour. Time for {THICKNESS}μm: {TIME_RANGE}"
        },

        # Low Phosphorous - Nicklad ELV 824
        {
          id: 'LOW_PHOS_NICKLAD_ELV_824',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cope_rolled_aluminium', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'low_phosphorous',
          target_thickness: nil,
          deposition_rate_range: [6.8, 12.2],
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Nicklad ELV 824 (Low Phos) at 82-91°C. Deposition rate: 6.8-12.2 μm/hour. Time for {THICKNESS}μm: {TIME_RANGE}"
        },

        # PTFE Composite - Nicklad Ice
        {
          id: 'PTFE_NICKLAD_ICE',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cope_rolled_aluminium', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'ptfe_composite',
          target_thickness: nil,
          deposition_rate_range: [5.0, 11.0],
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Nicklad Ice (PTFE composite) at 82-88°C. Deposition rate: 5.0-11.0 μm/hour. Time for {THICKNESS}μm: {TIME_RANGE}"
        }
      ]

      # Interpolate thickness and time into template placeholders
      base_operations.map do |operation_data|
        operation_text = if target_thickness_um.present? && target_thickness_um > 0
          time_data = calculate_plating_time(operation_data[:id], target_thickness_um)
          if time_data
            operation_data[:operation_text]
              .gsub('{THICKNESS}', target_thickness_um.to_s)
              .gsub('{TIME_RANGE}', time_data[:formatted_time_range])
          else
            # Fallback if time calculation fails
            operation_data[:operation_text]
              .gsub('{THICKNESS}', target_thickness_um.to_s)
              .gsub('{TIME_RANGE}', 'calculation unavailable')
          end
        else
          # If no thickness provided, remove template placeholders
          operation_data[:operation_text].gsub('. Time for {THICKNESS}μm: {TIME_RANGE}', '')
        end

        # Append OCV monitoring for aerospace/defense
        if aerospace_defense
          ocv_text = build_time_temp_monitoring_text
          operation_text += "\n\n**OCV Monitoring:**\n#{ocv_text}"
        end

        Operation.new(
          id: operation_data[:id],
          alloys: operation_data[:alloys],
          process_type: operation_data[:process_type],
          enp_type: operation_data[:enp_type],
          target_thickness: operation_data[:target_thickness],
          deposition_rate_range: operation_data[:deposition_rate_range],
          vat_numbers: operation_data[:vat_numbers],
          operation_text: operation_text
        )
      end
    end

    # Helper method to calculate plating time for a given thickness
    def self.calculate_plating_time(operation_id, target_thickness_um)
      # Use a simple array lookup to avoid recursion issues
      base_operations = [
        { id: 'HIGH_PHOS_VANDALLOY_4100', deposition_rate_range: [12.0, 14.1] },
        { id: 'MEDIUM_PHOS_NICKLAD_767', deposition_rate_range: [18.0, 23.0] },
        { id: 'LOW_PHOS_NICKLAD_ELV_824', deposition_rate_range: [6.8, 18.2] },
        { id: 'PTFE_NICKLAD_ICE', deposition_rate_range: [5.0, 11.0] }
      ]

      operation_data = base_operations.find { |op| op[:id] == operation_id }
      return nil unless operation_data&.dig(:deposition_rate_range)

      min_rate, max_rate = operation_data[:deposition_rate_range]

      # Calculate time range (min time with max rate, max time with min rate)
      min_time_hours = target_thickness_um / max_rate
      max_time_hours = target_thickness_um / min_rate

      min_time_minutes = (min_time_hours * 60).round
      max_time_minutes = (max_time_hours * 60).round

      {
        min_hours: min_time_hours.round(2),
        max_hours: max_time_hours.round(2),
        min_minutes: min_time_minutes,
        max_minutes: max_time_minutes,
        formatted_time_range: "#{format_time(min_time_hours)} - #{format_time(max_time_hours)}"
      }
    end

    # Build time/temp monitoring text (no voltage for ENP)
    def self.build_time_temp_monitoring_text
      text_lines = []
      (1..3).each do |batch|
        text_lines << "Batch ___: Time ___    Temp ___°C"
      end
      text_lines.join("\n")
    end

    private

    def self.format_time(hours)
      if hours < 1
        "#{(hours * 60).round} min"
      elsif hours == hours.to_i
        "#{hours.to_i}h"
      else
        h = hours.to_i
        m = ((hours - h) * 60).round
        "#{h}h #{m}m"
      end
    end
  end
end
