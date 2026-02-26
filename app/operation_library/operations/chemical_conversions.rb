# app/operation_library/operations/chemical_conversions.rb
module OperationLibrary
  class ChemicalConversions
    def self.operations(aerospace_defense: false)
      base_operations = [
        # Iridite NCP Chemical Conversion - 7-10 minute variant
        {
          id: 'IRIDITE_NCP_7_TO_10_MIN',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: 'Convert in Iridite NCP at 28-45°C for 7-10 mins'
        },

        # Iridite NCP Chemical Conversion - 4-5 minute variant
        {
          id: 'IRIDITE_NCP_4_TO_5_MIN',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: 'Convert in Iridite NCP at 28-45°C for 4-5 mins'
        },

        # Alochrom 1200 Chemical Conversion - Class 1A (Corrosion Resistance)
        {
          id: 'ALOCHROM_1200_CLASS_1A',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541 Type I Class 1A, Def Stan 03-18 Code C (FOR MAXIMUM CORROSION RESISTANCE)',
          operation_text: 'Chromate convert in Alochrom 1200 at 18-27°C for 4-5 mins (FOR MAXIMUM CORROSION RESISTANCE)'
        },

        # Alochrom 1200 Chemical Conversion - Class 3 (Electrical Conductivity)
        {
          id: 'ALOCHROM_1200_CLASS_3',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541 Type I Class 3, Def Stan 03-18 Code C (FOR MAXIMUM ELECTRICAL CONDUCTIVITY)',
          operation_text: 'Chromate convert in Alochrom 1200 at 18-27°C for 2-3 mins (FOR MAXIMUM ELECTRICAL CONDUCTIVITY)'
        },

        # SurTec 650V Chemical Conversion
        {
          id: 'SURTEC_650V',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: 'Immerse parts in SurTec 650V immerse at 30-40°C for 3-4 mins. Ensure solution is agitated before and during use'
        },

        # Iridite 15 with Keycote and Chromic Etch Process
        {
          id: 'IRIDITE_15',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: <<~TEXT.strip
            1. Keycote 245 at 35-80°C for 30 to 60 secs
            2. Chromic etch for 4 secs
            3. Treat in Iridite 15 at 18-27°C for 1-3 mins
          TEXT
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
          specifications: op_data[:specifications],
          operation_text: operation_text
        )
      end
    end

    # Build time/temp monitoring text (no voltage for chemical conversion)
    def self.build_time_temp_monitoring_text
      text_lines = []
      (1..3).each do |batch|
        text_lines << "Batch ___: Time ___    Temp ___°C"
      end
      text_lines.join("\n")
    end
  end
end
