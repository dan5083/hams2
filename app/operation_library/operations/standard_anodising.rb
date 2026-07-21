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

      # Append OCV monitoring for aerospace/defense
      if aerospace_defense
        ocv_text = build_voltage_monitoring_text(data[:operation_text])
        operation_text += "\n\n**OCV Monitoring:**\n#{ocv_text}"
      end

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
        # ---------------------------------------------------------------
        # 6000 Series (excluding 6063) - all vat 6, 16V
        # 5μm process runs at 15V (the 6082 10-minute process)
        # ---------------------------------------------------------------
        {
          id: '6000_STANDARD_5',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [6],
          operation_text: "Standard anodise 15V over 10 minutes in vat 6"
        },
        {
          id: '6000_STANDARD_10',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 15 minutes in vat 6"
        },
        {
          id: '6000_STANDARD_15',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 20 minutes in vat 6"
        },
        {
          id: '6000_STANDARD_20',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 25 minutes in vat 6"
        },
        {
          id: '6000_STANDARD_25',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 30 minutes in vat 6"
        },
        {
          id: '6000_STANDARD_30',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 35 minutes in vat 6"
        },
        {
          id: '6000_STANDARD_35',
          alloys: ['6000_series_ex6063'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 35,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 40 minutes in vat 6"
        },

        # ---------------------------------------------------------------
        # 7075 / 7050 / 7021 / 2099 - all vat 6, 16V
        # ---------------------------------------------------------------
        {
          id: '7XXX_STANDARD_5',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 10 minutes in vat 6"
        },
        {
          id: '7XXX_STANDARD_10',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 15 minutes in vat 6"
        },
        {
          id: '7XXX_STANDARD_15',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 20 minutes in vat 6"
        },
        {
          id: '7XXX_STANDARD_20',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 25 minutes in vat 6"
        },
        {
          id: '7XXX_STANDARD_25',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 25 minutes in vat 6"
        },
        {
          id: '7XXX_STANDARD_30',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 30 minutes in vat 6"
        },
        {
          id: '7XXX_STANDARD_35',
          alloys: ['7075', '7050', '7021', '2099'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 35,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 35 minutes in vat 6"
        },

        # ---------------------------------------------------------------
        # 2014 / H15 / LT68 - all vat 6, 16V
        # ---------------------------------------------------------------
        {
          id: '2014_STANDARD_5',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 10 minutes in vat 6"
        },
        {
          id: '2014_STANDARD_10',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 15 minutes in vat 6"
        },
        {
          id: '2014_STANDARD_15',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 20 minutes in vat 6"
        },
        {
          id: '2014_STANDARD_20',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 25 minutes in vat 6"
        },
        {
          id: '2014_STANDARD_25',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 35 minutes in vat 6"
        },
        {
          id: '2014_STANDARD_30',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 40 minutes in vat 6"
        },
        {
          id: '2014_STANDARD_35',
          alloys: ['2014', 'h15', 'lt68'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 35,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 45 minutes in vat 6"
        },

        # ---------------------------------------------------------------
        # 5083 - all vat 6, 16V
        # ---------------------------------------------------------------
        {
          id: '5083_STANDARD_5',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 5,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 10 minutes in vat 6"
        },
        {
          id: '5083_STANDARD_10',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 10,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 15 minutes in vat 6"
        },
        {
          id: '5083_STANDARD_15',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 15,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 20 minutes in vat 6"
        },
        {
          id: '5083_STANDARD_20',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 20,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 25 minutes in vat 6"
        },
        {
          id: '5083_STANDARD_25',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 25,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 30 minutes in vat 6"
        },
        {
          id: '5083_STANDARD_30',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 30,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 35 minutes in vat 6"
        },
        {
          id: '5083_STANDARD_35',
          alloys: ['5083'],
          anodic_classes: ['class_1', 'class_2'],
          target_thickness: 35,
          vat_numbers: [6],
          operation_text: "Standard anodise 16V over 40 minutes in vat 6"
        }
      ]
    end
  end
end
