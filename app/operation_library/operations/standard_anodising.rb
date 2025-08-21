# app/operation_library/anodising/standard_anodising.rb
module OperationLibrary
  class AnodisingStandard
    def self.operations
      [
        # 5083 Alloy - 8-13Î¼m (= 10.5)
        Operation.new(
          id: '5083_STANDARD_10_5',
          alloys: ['5083'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10.5,
          vat_numbers: [6],
          operation_text: "Standard anodise 19V over 15 minutes in vat 6"
        ),

        # 5083 Alloy - 20Î¼m
        Operation.new(
          id: '5083_STANDARD_20',
          alloys: ['5083'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [12],
          operation_text: "Standard anodise 20V over 20 minutes in vat 12"
        ),

        # 6000 Series (excluding 6063) - 5Î¼m
        Operation.new(
          id: '6000_STANDARD_5',
          alloys: ['6000_series_ex6063'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [5],
          operation_text: "Standard anodise 15V over 15 minutes in vat 5"
        ),

        # 6000 Series (excluding 6063) - 10Î¼m
        Operation.new(
          id: '6000_STANDARD_10',
          alloys: ['6000_series_ex6063'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10,
          vat_numbers: [6],
          operation_text: "Standard anodise 18V over 10 minutes in vat 6"
        ),

        # 6000 Series (excluding 6063) - 15Î¼m
        Operation.new(
          id: '6000_STANDARD_15',
          alloys: ['6000_series_ex6063'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [6],
          operation_text: "Standard anodise 18V over 35 minutes in vat 6"
        ),

        # 6000 Series (excluding 6063) - 20Î¼m
        Operation.new(
          id: '6000_STANDARD_20',
          alloys: ['6000_series_ex6063'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 37 minutes in vat 6"
        ),

        # 6000 Series (excluding 6063) - 22.5Î¼m
        Operation.new(
          id: '6000_STANDARD_22_5',
          alloys: ['6000_series_ex6063'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 22.5,
          vat_numbers: [6],
          operation_text: "Standard anodise 18V over 30 minutes in vat 6"
        ),

        # 6000 Series (excluding 6063) - 25Î¼m
        Operation.new(
          id: '6000_STANDARD_25',
          alloys: ['6000_series_ex6063'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 40 minutes in vat 6"
        ),

        # 7075, 7050, 7021, 2099 - 25Î¼m
        Operation.new(
          id: '7XXX_STANDARD_25',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 14V over 40 minutes in vat 6"
        ),

        # 2014, H15, LT68 - 25Î¼m
        Operation.new(
          id: '2014_STANDARD_25',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 10V over 35 minutes in vat 6"
        ),

        # LM6 - 20Î¼m
        Operation.new(
          id: 'LM6_STANDARD_20',
          alloys: ['lm6'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 30 minutes in vat 6"
        ),

        # All Alloys (excluding 6063) - General Process - 6-13Î¼m (= 10.5)
        Operation.new(
          id: 'ALL_STANDARD_10_5',
          alloys: ['all_alloys_excluding_6063'],
          process_type: 'standard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10.5,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 30 minutes in vat 6"
        )
      ]
    end
  end
end
