# app/operation_library/operations/chromic_anodising.rb
module OperationLibrary
  class AnodisingChromic
    def self.operations
      [
        # Chromic Acid Anodise Process 1 - High voltage variant (available to multiple alloys, but ONLY option for 7075)
        Operation.new(
          id: 'CAA_40_50V_40MIN',
          alloys: ['general', 'aluminium', '6000_series', '7075', '2024'],
          process_type: 'chromic_anodising',
          target_thickness: 2.5, # Fixed thickness for chromic
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-40V (over 10 minutes), 40V (hold for 20 minutes), 40-50V (over 5 minutes), 50V (hold for 5 minutes)'
        ),

        # Chromic Acid Anodise Process 2 - Standard voltage variant (NOT available for 7075)
        Operation.new(
          id: 'CAA_22V_37MIN',
          alloys: ['general', 'aluminium', '6000_series', '2024'],
          process_type: 'chromic_anodising',
          target_thickness: 2.5, # Fixed thickness for chromic
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-22V (over 7 minutes), 22V (hold over 30 minutes)'
        )
      ]
    end
  end
end
