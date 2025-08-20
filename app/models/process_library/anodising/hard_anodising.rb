# app/models/process_library/anodising/hard_anodising.rb
module ProcessLibrary
  class AnodisingHard
    def self.processes
      [
        # Lufthansa Special
        Process.new(
          id: 'LUFTHANSA_HARD_50',
          alloys: ['lufthansa_aluminium'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V-->45V over 35 minutes in vat 5"
        ),

        # Titanium (Rose Gold)
        Process.new(
          id: 'TITANIUM_ROSE_GOLD_HARD_2',
          alloys: ['titanium'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 2,
          vat_numbers: [5],
          operation_text: "Hard anodise 15V-->20V over 2 minutes in vat 5"
        ),

        # 5054 Alloy - 50μm
        Process.new(
          id: '5054_HARD_50',
          alloys: ['5054'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 50,
          vat_numbers: [12],
          operation_text: "Hard anodise 25V-->45V over 45 minutes in vat 12"
        ),

        # 5054 Alloy - 60μm
        Process.new(
          id: '5054_HARD_60',
          alloys: ['5054'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 60,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 26V-->50V over 30 minutes in any of vats 1, 3, 9, 12"
        ),

        # 6000 Series (excluding 6063) - 5μm
        Process.new(
          id: '6000_HARD_5_MULTI',
          alloys: ['6000_series_ex6063'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 5,
          vat_numbers: [1, 2, 3, 5, 9, 12],
          operation_text: "Hard anodise 15V-->15V over 15 minutes in any of vats 1, 2, 3, 5, 9, 12"
        ),

        Process.new(
          id: '6000_HARD_5_VAT5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [5],
          operation_text: "Hard anodise 15V-->15V over 15 minutes in vat 5"
        ),

        # 6000 Series (excluding 6063) - 10μm
        Process.new(
          id: '6000_HARD_10_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 10,
          vat_numbers: [1, 2, 3, 5, 12],
          operation_text: "Hard anodise 25V-->30V over 10 minutes in any of vats 1, 2, 3, 5, 12"
        ),

        # 6000 Series (excluding 6063) - 12.5μm
        Process.new(
          id: '6000_HARD_12_5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 12.5,
          vat_numbers: [1, 2, 3, 12],
          operation_text: "Hard anodise 18V-->18V over 30 minutes in any of vats 1, 2, 3, 12"
        ),

        # 6000 Series (excluding 6063) - 15μm
        Process.new(
          id: '6000_HARD_15_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 15,
          vat_numbers: [1, 2, 3, 5, 12],
          operation_text: "Hard anodise 25V-->30V over 15 minutes in any of vats 1, 2, 3, 5, 12"
        ),

        # 6000 Series (excluding 6063) - 25μm
        Process.new(
          id: '6000_HARD_25_VAT5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->32V over 30 minutes in vat 5"
        ),

        Process.new(
          id: '6000_HARD_25_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->35V over 20 minutes in any of vats 1, 3, 9, 12"
        ),

        # 6000 Series (excluding 6063) - 30μm
        Process.new(
          id: '6000_HARD_30_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 30,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->35V over 30 minutes in any of vats 1, 3, 9, 12"
        ),

        Process.new(
          id: '6000_HARD_30_VAT5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 30,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->32V over 30 minutes in vat 5"
        ),

        # 6000 Series (excluding 6063) - 35μm
        Process.new(
          id: '6000_HARD_35_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 35,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V-->40V over 20 minutes in any of vats 1, 3, 9, 12"
        ),

        Process.new(
          id: '6000_HARD_35_VAT5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 35,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->32V over 30 minutes in vat 5"
        ),

        # 6000 Series (excluding 6063) - 40/42.5μm
        Process.new(
          id: '6000_HARD_42_5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 42.5,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->45V over 30 minutes in vat 5"
        ),

        # 6000 Series (excluding 6063) - 45μm
        Process.new(
          id: '6000_HARD_45_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 45,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->45V over 30 minutes in any of vats 1, 3, 9, 12"
        ),

        Process.new(
          id: '6000_HARD_45_VAT5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 45,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->40V over 35 minutes in vat 5"
        ),

        # 6000 Series (excluding 6063) - 50μm
        Process.new(
          id: '6000_HARD_50_VAT5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->40V over 30 minutes in vat 5"
        ),

        Process.new(
          id: '6000_HARD_50_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 50,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in any of vats 1, 3, 9, 12"
        ),

        # 6000 Series (excluding 6063) - 52.5μm
        Process.new(
          id: '6000_HARD_52_5_MULTI',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 52.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->50V over 45 minutes in any of vats 1, 3, 9, 12"
        ),

        Process.new(
          id: '6000_HARD_52_5_VAT5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 52.5,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->40V over 35 minutes in vat 5"
        ),

        Process.new(
          id: '6000_HARD_52_5_VAT3_DYED',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 52.5,
          vat_numbers: [3],
          operation_text: "Hard anodise 25V-->50V over 45 minutes in vat 3"
        ),

        Process.new(
          id: '6000_HARD_52_5_VAT3_FAST',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 52.5,
          vat_numbers: [3],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in vat 3"
        ),

        # 6000 Series (excluding 6063) - 55μm
        Process.new(
          id: '6000_HARD_55',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 55,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->50V over 50 minutes in any of vats 1, 3, 9, 12"
        ),

        # 6000 Series (excluding 6063) - 57.5μm
        Process.new(
          id: '6000_HARD_57_5_DYED',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 57.5,
          vat_numbers: [1, 5],
          operation_text: "Hard anodise 25V-->55V over 50 minutes in any of vats 1, 5"
        ),

        Process.new(
          id: '6000_HARD_57_5_UNDYED',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 57.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->55V over 50 minutes in any of vats 1, 3, 9, 12"
        ),

        # 6000 Series (excluding 6063) - 60μm
        Process.new(
          id: '6000_HARD_60',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 60,
          vat_numbers: [3],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in vat 3"
        ),

        # 6000 Series (excluding 6063) - 62.5μm
        Process.new(
          id: '6000_HARD_62_5',
          alloys: ['6000_series'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 62.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V-->60V over 60 minutes in any of vats 1, 3, 9, 12"
        ),

        # 7075, 7050, 7021, 2099 - 10μm
        Process.new(
          id: '7XXX_HARD_10_UNDYED',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 10,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V-->25V over 10 minutes in vat 2"
        ),

        Process.new(
          id: '7XXX_HARD_10_DYED',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 10,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V-->25V over 10 minutes in vat 2"
        ),

        # 7075, 7050, 7021, 2099 - 15μm
        Process.new(
          id: '7XXX_HARD_15_UNDYED',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 15,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V-->25V over 10 minutes in vat 2"
        ),

        Process.new(
          id: '7XXX_HARD_15_DYED',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 15,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V-->25V over 10 minutes in vat 2"
        ),

        # 7075, 7050, 7021, 2099 - 20μm
        Process.new(
          id: '7XXX_HARD_20',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V-->30V over 10 minutes in vat 2"
        ),

        # 7075, 7050, 7021, 2099 - 22.5μm
        Process.new(
          id: '7XXX_HARD_22_5_MULTI',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 22.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V-->32V over 13 minutes in any of vats 1, 3, 9, 12"
        ),

        Process.new(
          id: '7XXX_HARD_22_5_VAT5',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 22.5,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V-->27V over 13 minutes in vat 5"
        ),

        Process.new(
          id: '7XXX_HARD_22_5_VAT2',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 22.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->32V over 9 minutes in vat 2"
        ),

        # 7075, 7050, 7021, 2099 - 25μm
        Process.new(
          id: '7XXX_HARD_25_MULTI',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 25,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V-->32V over 15 minutes in any of vats 1, 3, 9, 12"
        ),

        Process.new(
          id: '7XXX_HARD_25_VAT5',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 25,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V-->27V over 15 minutes in vat 5"
        ),

        Process.new(
          id: '7XXX_HARD_25_VAT2',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->32V over 10 minutes in vat 2"
        ),

        # 7075, 7050, 7021, 2099, 7075 Tooling plate - 40μm
        Process.new(
          id: '7XXX_HARD_40_VAT5',
          alloys: ['7075', '7050', '7021', '2099', '7075_tooling_plate'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 40,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->30V over 25 minutes in vat 5"
        ),

        Process.new(
          id: '7XXX_HARD_40_MULTI',
          alloys: ['7075', '7050', '7021', '2099', '7075_tooling_plate'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 40,
          vat_numbers: [1, 3],
          operation_text: "Hard anodise 20V-->35V over 30 minutes in any of vats 1, 3"
        ),

        Process.new(
          id: '7XXX_HARD_40_VAT2',
          alloys: ['7075', '7050', '7021', '2099', '7075_tooling_plate'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 40,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V-->40V over 20 minutes in vat 2"
        ),

        # 7075, 7050, 7021, 2099 - 50μm
        Process.new(
          id: '7XXX_HARD_50_VAT3',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [3],
          operation_text: "Hard anodise 20V-->45V over 30 minutes in vat 3"
        ),

        Process.new(
          id: '7XXX_HARD_50_VAT5',
          alloys: ['7075', '7050', '7021', '2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->30V over 30 minutes in vat 5"
        ),

        # 2014, H15, LT68 - 10.5μm
        Process.new(
          id: '2014_HARD_10_5',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->30V over 10 minutes in vat 2"
        ),

        # 2014, H15, LT68 - 15μm
        Process.new(
          id: '2014_HARD_15',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->30V over 10 minutes in vat 2"
        ),

        # 2014, H15, LT68 - 25μm
        Process.new(
          id: '2014_HARD_25_VAT2',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->35V over 15 minutes in vat 2"
        ),

        Process.new(
          id: '2014_HARD_25_VAT3',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [3],
          operation_text: "Hard anodise 20V-->30V over 30 minutes in vat 3"
        ),

        # 2014, H15, LT68 - 30μm
        Process.new(
          id: '2014_HARD_30_VAT2',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->40V over 20 minutes in vat 2"
        ),

        Process.new(
          id: '2014_HARD_30_VAT5',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V-->30V over 30 minutes in vat 5"
        ),

        # 2014, H15, LT68 - 40μm
        Process.new(
          id: '2014_HARD_40',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 40,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in vat 2"
        ),

        # 2014, H15, LT68 - 47.5μm
        Process.new(
          id: '2014_HARD_47_5',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 47.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in vat 2"
        ),

        # 2014, H15, LT68 - 50μm
        Process.new(
          id: '2014_HARD_50_VAT2',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->60V over 30 minutes in vat 2"
        ),

        Process.new(
          id: '2014_HARD_50_VAT5',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V-->40V over 40 minutes in vat 5"
        ),

        # 2014, H15, LT68 - 55μm
        Process.new(
          id: '2014_HARD_55',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 55,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->55V over 30 minutes in vat 2, then hold at 30V for 10 minutes"
        ),

        # 2014, H15, LT68 - 70μm
        Process.new(
          id: '2014_HARD_70',
          alloys: ['2014', 'h15', 'lt68'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 70,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->65V over 35 minutes in vat 2"
        ),

        # 2618, H16 - 30μm
        Process.new(
          id: '2618_HARD_30_VAT2',
          alloys: ['2618', 'h16'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->40V over 20 minutes in vat 2"
        ),

        Process.new(
          id: '2618_HARD_30_VAT1',
          alloys: ['2618', 'h16'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [1],
          operation_text: "Hard anodise 25V-->40V over 30 minutes in vat 1"
        ),

        # 2618, H16 - 50μm
        Process.new(
          id: '2618_HARD_50',
          alloys: ['2618', 'h16'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [1, 2, 5],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in any of vats 1, 2, 5"
        ),

        # 2618, H16 - 55μm
        Process.new(
          id: '2618_HARD_55',
          alloys: ['2618', 'h16'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 55,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in vat 2, then hold at 50V for 5 minutes"
        ),

        # 2618, H16 - 57.5μm
        Process.new(
          id: '2618_HARD_57_5',
          alloys: ['2618', 'h16'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 57.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->60V over 30 minutes in vat 2"
        ),

        # 2099 - 35μm
        Process.new(
          id: '2099_HARD_35',
          alloys: ['2099'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 35,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->45V over 20 minutes in vat 2"
        ),

        # L174/L111/L111 - 52.5μm
        Process.new(
          id: 'L174_HARD_52_5',
          alloys: ['l174', 'l111'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 52.5,
          vat_numbers: [1, 3],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in any of vats 1, 3"
        ),

        # LM25 casting alloy - 30μm
        Process.new(
          id: 'LM25_HARD_30_MULTI',
          alloys: ['lm25_casting'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1'],
          target_thickness: 30,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->45V over 20 minutes in any of vats 1, 3, 9, 12"
        ),

        Process.new(
          id: 'LM25_HARD_30_VAT5',
          alloys: ['lm25_casting'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_2'],
          target_thickness: 30,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V-->45V over 20 minutes in vat 5"
        ),

        # LM25 casting alloy - 50μm
        Process.new(
          id: 'LM25_HARD_50',
          alloys: ['lm25_casting'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V-->50V over 30 minutes in any of vats 1, 3, 9, 12"
        ),

        # Scalmalloy - 25μm
        Process.new(
          id: 'SCALMALLOY_HARD_25',
          alloys: ['scalmalloy'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V-->35V over 10 minutes in vat 2, then hold at 35V for 4 minutes"
        ),

        # General Process - 25V-60V Over 60 mins
        Process.new(
          id: 'GENERAL_HARD_PROCESS',
          alloys: ['general'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 0,
          vat_numbers: [1, 3],
          operation_text: "Hard anodise 25V-->60V over 60 minutes in any of vats 1, 3"
        ),

        # 6026 Alloy
        Process.new(
          id: '6026_HARD_50',
          alloys: ['6026'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V-->60V over 60 minutes in any of vats 1, 3, 9, 12"
        ),

        # Titanium (Blue)
        Process.new(
          id: 'TITANIUM_BLUE_HARD_2',
          alloys: ['titanium'],
          process_type: 'hard_anodising',
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 2,
          vat_numbers: [6],
          operation_text: "Hard anodise 15V-->20V over 2 minutes in vat 6"
        )
      ]
    end
  end
end
