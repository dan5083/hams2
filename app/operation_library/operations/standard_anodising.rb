# app/operation_library/anodising/standard_anodising.rb
module OperationLibrary
  class AnodisingStandard
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
        " -- check film thickness against specification, if out of range inform an A stampholder\n-- record film thickness ___ μm"
      end

      operation_text = base_text + ending_text

      Operation.new(
        id: data[:id],
        alloys: data[:alloys],
        process_type: 'standard_anodising',
        anodic_classes: data[:anodic_classes],
        target_thickness: data[:target_thickness],
        vat_numbers: data[:vat_numbers],
        operation_text: operation_text
      )
    end

    def self.base_operations
      [
        # 5083 Alloy - 8-13μm (= 10.5)
        {
          id: '5083_STANDARD_10_5',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10.5,
          vat_numbers: [6],
          operation_text: "Standard anodise 19V over 15 minutes in vat 6"
        },

        # 5083 Alloy - 20μm
        {
          id: '5083_STANDARD_20',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [12],
          operation_text: "Standard anodise 20V over 20 minutes in vat 12"
        },

        # 6000 Series (excluding 6063) - 5μm
        {
          id: '6000_STANDARD_5',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [5],
          operation_text: "Standard anodise 15V over 15 minutes in vat 5"
        },

        # 6000 Series (excluding 6063) - 10μm
        {
          id: '6000_STANDARD_10',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10,
          vat_numbers: [6],
          operation_text: "Standard anodise 18V over 10 minutes in vat 6"
        },

        # 6000 Series (excluding 6063) - 15μm
        {
          id: '6000_STANDARD_15',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [6],
          operation_text: "Standard anodise 18V over 35 minutes in vat 6"
        },

        # 6000 Series (excluding 6063) - 20μm
        {
          id: '6000_STANDARD_20',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 37 minutes in vat 6"
        },

        # 6000 Series (excluding 6063) - 22.5μm
        {
          id: '6000_STANDARD_22_5',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 22.5,
          vat_numbers: [6],
          operation_text: "Standard anodise 18V over 30 minutes in vat 6"
        },

        # 6000 Series (excluding 6063) - 25μm
        {
          id: '6000_STANDARD_25',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 40 minutes in vat 6"
        },

        # 7075, 7050, 7021, 2099 - 25μm
        {
          id: '7XXX_STANDARD_25',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 14V over 40 minutes in vat 6"
        },

        # 2014, H15, LT68 - 25μm
        {
          id: '2014_STANDARD_25',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 10V over 35 minutes in vat 6"
        },

        # LM6 - 20μm
        {
          id: 'LM6_STANDARD_20',
          alloys: ['lm6'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 30 minutes in vat 6"
        },

        # All Alloys (excluding 6063) - General Process - 6-13μm (= 10.5)
        {
          id: 'ALL_STANDARD_10_5',
          alloys: ['all_alloys_excluding_6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10.5,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 30 minutes in vat 6"
        }
      ]
    end
  end
end
