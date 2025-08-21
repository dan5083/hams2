# app/operation_library/operations/electroless_nickel_plate.rb
module OperationLibrary
  class ElectrolessNickelPlate
    def self.operations
      [
        # High Phosphorous - Vandalloy 4100
        Operation.new(
          id: 'HIGH_PHOS_VANDALLOY_4100',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cast_aluminium_william_cope', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'high_phosphorous',
          target_thickness: nil, # Calculated based on time
          deposition_rate_range: [12.0, 14.1], # μm/hour
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Vandalloy 4100 (High Phos) at 82-91°C. Deposition rate: 12.0-14.1 μm/hour"
        ),

        # Medium Phosphorous - Nicklad 767
        Operation.new(
          id: 'MEDIUM_PHOS_NICKLAD_767',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cast_aluminium_william_cope', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'medium_phosphorous',
          target_thickness: nil, # Calculated based on time
          deposition_rate_range: [13.3, 17.1], # μm/hour
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Nicklad 767 (Medium Phos) at 82-91°C. Deposition rate: 13.3-17.1 μm/hour"
        ),

        # Low Phosphorous - Nicklad ELV 824
        Operation.new(
          id: 'LOW_PHOS_NICKLAD_ELV_824',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cast_aluminium_william_cope', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'low_phosphorous',
          target_thickness: nil, # Calculated based on time
          deposition_rate_range: [6.8, 18.2], # μm/hour (wide range due to process variability)
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Nicklad ELV 824 (Low Phos) at 82-91°C. Deposition rate: 6.8-18.2 μm/hour"
        ),

        # PTFE Composite - Nicklad Ice
        Operation.new(
          id: 'PTFE_NICKLAD_ICE',
          alloys: ['steel', 'stainless_steel', '316_stainless_steel', 'aluminium', 'copper', '2000_series_alloys', 'brass', 'stainless_steel_with_oxides', 'copper_sans_electrical_contact', 'cast_aluminium_william_cope', 'mclaren_sta142_procedure_d'],
          process_type: 'electroless_nickel_plating',
          enp_type: 'ptfe_composite',
          target_thickness: nil, # Calculated based on time
          deposition_rate_range: [5.0, 11.0], # μm/hour
          vat_numbers: [7, 8],
          operation_text: "Electroless nickel plate in Nicklad Ice (PTFE composite) at 82-88°C. Deposition rate: 5.0-11.0 μm/hour"
        )
      ]
    end

    # Helper method to calculate plating time for a given thickness
    def self.calculate_plating_time(operation_id, target_thickness_um)
      operation = operations.find { |op| op.id == operation_id }
      return nil unless operation&.deposition_rate_range

      min_rate, max_rate = operation.deposition_rate_range

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

    private

    def self.format_time(hours)
      if hours < 1
        "#{(hours * 60).round} minutes"
      elsif hours == hours.to_i
        "#{hours.to_i} #{'hour'.pluralize(hours.to_i)}"
      else
        h = hours.to_i
        m = ((hours - h) * 60).round
        "#{h} #{'hour'.pluralize(h)} #{m} #{'minute'.pluralize(m)}"
      end
    end
  end
end
