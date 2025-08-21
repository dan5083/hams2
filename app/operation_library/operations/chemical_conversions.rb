# app/operation_library/operations/chemical_conversions.rb
module OperationLibrary
  class ChemicalConversions
    def self.operations
      [
        # Iridite NCP Chemical Conversion - 7-10 minute variant
        Operation.new(
          id: 'IRIDITE_NCP_7_TO_10_MIN',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: 'Convert in Iridite NCP at 28-45°C for 7-10 mins'
        ),

        # Iridite NCP Chemical Conversion - 4-5 minute variant
        Operation.new(
          id: 'IRIDITE_NCP_4_TO_5_MIN',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: 'Convert in Iridite NCP at 28-45°C for 4-5 mins'
        ),

        # Alochrom 1200 Chemical Conversion
        Operation.new(
          id: 'ALOCHROM_1200',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541 Type I Class 1A and Class 3, Def Stan 03-18 Code C',
          operation_text: 'Chromate convert in Alochrom 1200 at 18-27°C for 2-5 mins'
        ),

        # SurTec 650V Chemical Conversion
        Operation.new(
          id: 'SURTEC_650V',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: 'Immerse parts in SurTec 650V immerse at 30-40°C for 3-4 mins. Ensure solution is agitated before and during use'
        ),

        # Iridite 15 with Keycote and Chromic Etch Process
        Operation.new(
          id: 'IRIDITE_15',
          process_type: 'chemical_conversion',
          specifications: 'MIL-DTL-5541F Type II (comprising non-hexavalent chromium conversion coatings)',
          operation_text: "1. Keycote 245 at 35-80°C for 30 to 60 secs\n2. Chromic etch for 4 secs\n3. Treat in Iridite 15 at 18-27°C for 1-3 mins"
        )
      ]
    end
  end
end
