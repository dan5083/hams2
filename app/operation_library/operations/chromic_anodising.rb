# app/operation_library/anodising/chromic_anodising.rb
module OperationLibrary
  class AnodisingChromic
    def self.operations(aerospace_defense = nil)
      # Default to aerospace/defense true if not specified to maintain existing behavior
      aerospace_defense = true if aerospace_defense.nil?

      base_operations.map do |operation_data|
        create_operation(operation_data, aerospace_defense)
      end
    end

    private

    def self.create_operation(data, aerospace_defense)
      # The ending text is now dynamically generated based on aerospace/defense flag
      base_text = data[:operation_text]

      ending_text = if aerospace_defense
        " -- check film thickness against specification, if out of range inform an A stampholder"
      else
        " -- check film thickness against specification, if out of range inform an A stampholder\n-- record film thickness ___μm"
      end

      operation_text = base_text + ending_text

      Operation.new(
        id: data[:id],
        alloys: data[:alloys],
        process_type: 'chromic_anodising',
        anodic_classes: data[:anodic_classes] || [],
        target_thickness: data[:target_thickness] || 0,
        vat_numbers: data[:vat_numbers],
        operation_text: operation_text
      )
    end

    def self.base_operations
      [
        # Chromic Acid Anodise Process 1 - High voltage variant (NOT available for 7075)
        {
          id: 'CAA_40_50V_40MIN',
          alloys: ['general', 'aluminium', '6000_series', '2024'],
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-40V (over 10 minutes), 40V (hold for 20 minutes), 40-50V (over 5 minutes), 50V (hold for 5 minutes)'
        },

        # Chromic Acid Anodise Process 2 - Standard voltage variant (available to all alloys, but ONLY option for 7075)
        {
          id: 'CAA_22V_37MIN',
          alloys: ['general', 'aluminium', '6000_series', '7075', '2024'],
          vat_numbers: [10],
          operation_text: 'Chromic acid anodise in Vat 10 at 38-42°C. 0-22V (over 7 minutes), 22V (hold over 30 minutes)'
        }
      ]
    end
  end
end
