# app/operation_library/anodising/hard_anodising.rb
module OperationLibrary
  class AnodisingHard
    def self.operations(aerospace_defense = nil)
        Rails.logger.info "🔍 AnodisingHard.operations called with aerospace_defense: #{aerospace_defense.inspect}"

      # Default to aerospace/defense true if not specified to maintain existing behavior
      aerospace_defense = true if aerospace_defense.nil?

        Rails.logger.info "🔍 AnodisingHard.operations using aerospace_defense: #{aerospace_defense.inspect}"

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

    # Append OCV monitoring for aerospace/defense
    if aerospace_defense
      ocv_text = build_voltage_monitoring_text(data[:operation_text])
      operation_text += "\n\n**OCV Monitoring:**\n#{ocv_text}"
    end

    Operation.new(
      id: data[:id],
      alloys: data[:alloys],
      process_type: 'hard_anodising',
      anodic_classes: data[:anodic_classes],
      target_thickness: data[:target_thickness],
      vat_numbers: data[:vat_numbers],
      operation_text: operation_text
    )
  end

  def self.build_voltage_monitoring_text(operation_text)
    # Extract total minutes from operation text
    time_match = operation_text.match(/over (\d+) minutes/)
    total_minutes = time_match ? time_match[1].to_i : 20

    # Calculate 5-minute intervals
    intervals = (total_minutes / 5.0).ceil

    # Build monitoring text for 3 batches
    text_lines = []
    (1..3).each do |batch|
      interval_texts = []
      (1..intervals).each do |interval|
        time_mark = interval * 5
        interval_texts << "#{time_mark}min: ___V"
      end
      text_lines << "Batch ___: Temp ___°C [#{interval_texts.join(' | ')}]"
    end

    text_lines.join("\n")
  end

    def self.base_operations
      [
        # Lufthansa Special
        {
          id: 'LUFTHANSA_HARD_50',
          alloys: ['lufthansa_aluminium'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V↗️45V over 35 minutes in vat 5"
        },

        # Titanium (Rose Gold)
        {
          id: 'TITANIUM_ROSE_GOLD_HARD_2',
          alloys: ['titanium'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 2,
          vat_numbers: [5],
          operation_text: "Hard anodise 15V↗️20V over 2 minutes in vat 5"
        },

        # 5054 Alloy - 50μm
        {
          id: '5054_HARD_50',
          alloys: ['5054'],
          anodic_classes: ['class_1'],
          target_thickness: 50,
          vat_numbers: [12],
          operation_text: "Hard anodise 25V↗️45V over 45 minutes in vat 12"
        },

        # 5054 Alloy - 60μm
        {
          id: '5054_HARD_60',
          alloys: ['5054'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 60,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 26V↗️50V over 30 minutes in any of vats 1, 3, 9, 12"
        },

        # 6000 Series (excluding 6063) - 5μm
        {
          id: '6000_HARD_5_MULTI',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1'],
          target_thickness: 5,
          vat_numbers: [1, 2, 3, 5, 9, 12],
          operation_text: "Hard anodise 15V↗️15V over 15 minutes in any of vats 1, 2, 3, 5, 9, 12"
        },

        {
          id: '6000_HARD_5_VAT5',
          alloys: ['6000_series'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [5],
          operation_text: "Hard anodise 15V↗️15V over 15 minutes in vat 5"
        },

        # 6000 Series (excluding 6063) - 10μm
        {
          id: '6000_HARD_10_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 10,
          vat_numbers: [1, 2, 3, 5, 12],
          operation_text: "Hard anodise 25V↗️30V over 10 minutes in any of vats 1, 2, 3, 5, 12"
        },

        # 6000 Series (excluding 6063) - 12.5μm
        {
          id: '6000_HARD_12_5',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 12.5,
          vat_numbers: [1, 2, 3, 12],
          operation_text: "Hard anodise 18V↗️18V over 30 minutes in any of vats 1, 2, 3, 12"
        },

        # 6000 Series (excluding 6063) - 15μm
        {
          id: '6000_HARD_15_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 15,
          vat_numbers: [1, 2, 3, 5, 12],
          operation_text: "Hard anodise 25V↗️30V over 15 minutes in any of vats 1, 2, 3, 5, 12"
        },

        # 6000 Series (excluding 6063) - 25μm
        {
          id: '6000_HARD_25_VAT5',
          alloys: ['6000_series'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️32V over 30 minutes in vat 5"
        },

        {
          id: '6000_HARD_25_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️35V over 20 minutes in any of vats 1, 3, 9, 12"
        },

        # 6000 Series (excluding 6063) - 30μm
        {
          id: '6000_HARD_30_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 30,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️35V over 30 minutes in any of vats 1, 3, 9, 12"
        },

        {
          id: '6000_HARD_30_VAT5',
          alloys: ['6000_series'],
          anodic_classes: ['class_2'],
          target_thickness: 30,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️32V over 30 minutes in vat 5"
        },

        # 6000 Series (excluding 6063) - 35μm
        {
          id: '6000_HARD_35_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 35,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V↗️40V over 20 minutes in any of vats 1, 3, 9, 12"
        },

        {
          id: '6000_HARD_35_VAT5',
          alloys: ['6000_series'],
          anodic_classes: ['class_2'],
          target_thickness: 35,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️32V over 30 minutes in vat 5"
        },

        # 6000 Series (excluding 6063) - 40/42.5μm
        {
          id: '6000_HARD_42_5',
          alloys: ['6000_series'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 42.5,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️45V over 30 minutes in vat 5"
        },

        # 6000 Series (excluding 6063) - 45μm
        {
          id: '6000_HARD_45_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 45,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️45V over 30 minutes in any of vats 1, 3, 9, 12"
        },

        {
          id: '6000_HARD_45_VAT5',
          alloys: ['6000_series'],
          anodic_classes: ['class_2'],
          target_thickness: 45,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️40V over 35 minutes in vat 5"
        },

        # 6000 Series (excluding 6063) - 50μm
        {
          id: '6000_HARD_50_VAT5',
          alloys: ['6000_series'],
          anodic_classes: ['class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️40V over 30 minutes in vat 5"
        },

        {
          id: '6000_HARD_50_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 50,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in any of vats 1, 3, 9, 12"
        },

        # 6000 Series (excluding 6063) - 52.5μm
        {
          id: '6000_HARD_52_5_MULTI',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 52.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️50V over 45 minutes in any of vats 1, 3, 9, 12"
        },

        {
          id: '6000_HARD_52_5_VAT5',
          alloys: ['6000_series'],
          anodic_classes: ['class_2'],
          target_thickness: 52.5,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️40V over 35 minutes in vat 5"
        },

        {
          id: '6000_HARD_52_5_VAT3_DYED',
          alloys: ['6000_series'],
          anodic_classes: ['class_2'],
          target_thickness: 52.5,
          vat_numbers: [3],
          operation_text: "Hard anodise 25V↗️50V over 45 minutes in vat 3"
        },

        {
          id: '6000_HARD_52_5_VAT3_FAST',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 52.5,
          vat_numbers: [3],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in vat 3"
        },

        # 6000 Series (excluding 6063) - 55μm
        {
          id: '6000_HARD_55',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 55,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️50V over 50 minutes in any of vats 1, 3, 9, 12"
        },

        # 6000 Series (excluding 6063) - 57.5μm
        {
          id: '6000_HARD_57_5_DYED',
          alloys: ['6000_series'],
          anodic_classes: ['class_2'],
          target_thickness: 57.5,
          vat_numbers: [1, 5],
          operation_text: "Hard anodise 25V↗️55V over 50 minutes in any of vats 1, 5"
        },

        {
          id: '6000_HARD_57_5_UNDYED',
          alloys: ['6000_series'],
          anodic_classes: ['class_1'],
          target_thickness: 57.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️55V over 50 minutes in any of vats 1, 3, 9, 12"
        },

        # 6000 Series (excluding 6063) - 60μm
        {
          id: '6000_HARD_60',
          alloys: ['6000_series'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 60,
          vat_numbers: [3],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in vat 3"
        },

        # 6000 Series (excluding 6063) - 62.5μm
        {
          id: '6000_HARD_62_5',
          alloys: ['6000_series'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 62.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V↗️60V over 60 minutes in any of vats 1, 3, 9, 12"
        },

        # 7075, 7050, 7021, 2099 - 10μm
        {
          id: '7XXX_HARD_10_UNDYED',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1'],
          target_thickness: 10,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V↗️25V over 10 minutes in vat 2"
        },

        {
          id: '7XXX_HARD_10_DYED',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_2'],
          target_thickness: 10,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V↗️25V over 10 minutes in vat 2"
        },

        # 7075, 7050, 7021, 2099 - 15μm
        {
          id: '7XXX_HARD_15_UNDYED',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1'],
          target_thickness: 15,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V↗️25V over 10 minutes in vat 2"
        },

        {
          id: '7XXX_HARD_15_DYED',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_2'],
          target_thickness: 15,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V↗️25V over 10 minutes in vat 2"
        },

        # 7075, 7050, 7021, 2099 - 20μm
        {
          id: '7XXX_HARD_20',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V↗️30V over 10 minutes in vat 2"
        },

        # 7075, 7050, 7021, 2099 - 22.5μm
        {
          id: '7XXX_HARD_22_5_MULTI',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1'],
          target_thickness: 22.5,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V↗️32V over 13 minutes in any of vats 1, 3, 9, 12"
        },

        {
          id: '7XXX_HARD_22_5_VAT5',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_2'],
          target_thickness: 22.5,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V↗️27V over 13 minutes in vat 5"
        },

        {
          id: '7XXX_HARD_22_5_VAT2',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 22.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️32V over 9 minutes in vat 2"
        },

        # 7075, 7050, 7021, 2099 - 25μm
        {
          id: '7XXX_HARD_25_MULTI',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1'],
          target_thickness: 25,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V↗️32V over 15 minutes in any of vats 1, 3, 9, 12"
        },

        {
          id: '7XXX_HARD_25_VAT5',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_2'],
          target_thickness: 25,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V↗️27V over 15 minutes in vat 5"
        },

        {
          id: '7XXX_HARD_25_VAT2',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️32V over 10 minutes in vat 2"
        },

     # 7075, 7050, 7021, 2099, 7075 Tooling plate - 40μm
        {
          id: '7XXX_HARD_40_VAT5',
          alloys: ['7075', '7050', '7021', '2099', '7075_tooling_plate'],
          anodic_classes: ['class_2'],
          target_thickness: 40,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️30V over 25 minutes in vat 5"
        },

        {
          id: '7XXX_HARD_40_MULTI',
          alloys: ['7075', '7050', '7021', '2099', '7075_tooling_plate'],
          anodic_classes: ['class_1'],
          target_thickness: 40,
          vat_numbers: [1, 3],
          operation_text: "Hard anodise 20V↗️35V over 30 minutes in any of vats 1, 3"
        },

        {
          id: '7XXX_HARD_40_VAT2',
          alloys: ['7075', '7050', '7021', '2099', '7075_tooling_plate'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 40,
          vat_numbers: [2],
          operation_text: "Hard anodise 20V↗️40V over 20 minutes in vat 2"
        },

        # 7075, 7050, 7021, 2099 - 50μm
        {
          id: '7XXX_HARD_50_VAT3',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [3],
          operation_text: "Hard anodise 20V↗️45V over 30 minutes in vat 3"
        },

        {
          id: '7XXX_HARD_50_VAT5',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️30V over 30 minutes in vat 5"
        },

        # 2014, H15, LT68 - 10.5μm
        {
          id: '2014_HARD_10_5',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️30V over 10 minutes in vat 2"
        },

        # 2014, H15, LT68 - 15μm
        {
          id: '2014_HARD_15',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️30V over 10 minutes in vat 2"
        },

        # 2014, H15, LT68 - 25μm
        {
          id: '2014_HARD_25_VAT2',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️35V over 15 minutes in vat 2"
        },

        {
          id: '2014_HARD_25_VAT3',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [3],
          operation_text: "Hard anodise 20V↗️30V over 30 minutes in vat 3"
        },

        # 2014, H15, LT68 - 30μm
        {
          id: '2014_HARD_30_VAT2',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️40V over 20 minutes in vat 2"
        },

        {
          id: '2014_HARD_30_VAT5',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V↗️30V over 30 minutes in vat 5"
        },

        # 2014, H15, LT68 - 40μm
        {
          id: '2014_HARD_40',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 40,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in vat 2"
        },

        # 2014, H15, LT68 - 47.5μm
        {
          id: '2014_HARD_47_5',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 47.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in vat 2"
        },

        # 2014, H15, LT68 - 50μm
        {
          id: '2014_HARD_50_VAT2',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️60V over 30 minutes in vat 2"
        },

        {
          id: '2014_HARD_50_VAT5',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [5],
          operation_text: "Hard anodise 20V↗️40V over 40 minutes in vat 5"
        },

        # 2014, H15, LT68 - 55μm
        {
          id: '2014_HARD_55',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 55,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️55V over 30 minutes in vat 2, then hold at 30V for 10 minutes"
        },

        # 2014, H15, LT68 - 70μm
        {
          id: '2014_HARD_70',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 70,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️65V over 35 minutes in vat 2"
        },

        # 2618, H16 - 30μm
        {
          id: '2618_HARD_30_VAT2',
          alloys: ['2618', 'h16'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️40V over 20 minutes in vat 2"
        },

        {
          id: '2618_HARD_30_VAT1',
          alloys: ['2618', 'h16'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [1],
          operation_text: "Hard anodise 25V↗️40V over 30 minutes in vat 1"
        },

        # 2618, H16 - 50μm
        {
          id: '2618_HARD_50',
          alloys: ['2618', 'h16'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [1, 2, 5],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in any of vats 1, 2, 5"
        },

        # 2618, H16 - 55μm
        {
          id: '2618_HARD_55',
          alloys: ['2618', 'h16'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 55,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in vat 2, then hold at 50V for 5 minutes"
        },

        # 2618, H16 - 57.5μm
        {
          id: '2618_HARD_57_5',
          alloys: ['2618', 'h16'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 57.5,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️60V over 30 minutes in vat 2"
        },

        # 2099 - 35μm
        {
          id: '2099_HARD_35',
          alloys: ['2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 35,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️45V over 20 minutes in vat 2"
        },

        # L174/L111/L111 - 52.5μm
        {
          id: 'L174_HARD_52_5',
          alloys: ['l174', 'l111'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 52.5,
          vat_numbers: [1, 3],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in any of vats 1, 3"
        },

        # LM25 casting alloy - 30μm
        {
          id: 'LM25_HARD_30_MULTI',
          alloys: ['lm25_casting'],
          anodic_classes: ['class_1'],
          target_thickness: 30,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️45V over 20 minutes in any of vats 1, 3, 9, 12"
        },

        {
          id: 'LM25_HARD_30_VAT5',
          alloys: ['lm25_casting'],
          anodic_classes: ['class_2'],
          target_thickness: 30,
          vat_numbers: [5],
          operation_text: "Hard anodise 25V↗️45V over 20 minutes in vat 5"
        },

        # LM25 casting alloy - 50μm
        {
          id: 'LM25_HARD_50',
          alloys: ['lm25_casting'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 25V↗️50V over 30 minutes in any of vats 1, 3, 9, 12"
        },

        # Scalmalloy - 25μm
        {
          id: 'SCALMALLOY_HARD_25',
          alloys: ['scalmalloy'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [2],
          operation_text: "Hard anodise 25V↗️35V over 10 minutes in vat 2, then hold at 35V for 4 minutes"
        },

        # General Process - 25V-60V Over 60 mins
        {
          id: 'GENERAL_HARD_PROCESS',
          alloys: ['general'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 0,
          vat_numbers: [1, 3],
          operation_text: "Hard anodise 25V↗️60V over 60 minutes in any of vats 1, 3"
        },

        # 6026 Alloy
        {
          id: '6026_HARD_50',
          alloys: ['6026'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 50,
          vat_numbers: [1, 3, 9, 12],
          operation_text: "Hard anodise 20V↗️60V over 60 minutes in any of vats 1, 3, 9, 12"
        },

        # Titanium (Blue)
        {
          id: 'TITANIUM_BLUE_HARD_2',
          alloys: ['titanium'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 2,
          vat_numbers: [6],
          operation_text: "Hard anodise 15V↗️20V over 2 minutes in vat 6"
        }
      ]
    end
  end
end
