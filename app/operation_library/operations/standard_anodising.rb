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

    # OCV spec, chromic-doctrine (see AnodisingChromic): the op text carries
    # the process and the instruction, never blanks; WHAT gets recorded is
    # declared here and drawn by the renderer, on screen or on paper.
    #
    # Standard anodise ramps read every 5 minutes for the length of the
    # cycle - the shape the old baked-in "**OCV Monitoring:**" text block
    # drew as ___V blanks - derived from the op text's "over N minutes".
    #
    # Measured film thickness is captured on BOTH bases: the text tells the
    # operator to check it against specification either way, so there is no
    # reading of this job where the figure isn't taken. Aero/defence adds
    # temperature and the voltage trace on top, per IP2007 sequential capture.
    def self.ocv_spec(operation_text, aerospace_defense)
      if aerospace_defense
        OcvSpecs.anodise_ramp(total_minutes_from(operation_text))
      else
        OcvSpecs.fields(:film_thickness, basis: :general)
      end
    end

    def self.total_minutes_from(operation_text)
      match = operation_text.match(/over (\d+) minutes/)
      match ? match[1].to_i : 20
    end

    private

    def self.create_operation(data, aerospace_defense)
      operation_text = data[:operation_text] +
        " -- check film thickness against specification, if out of range inform an A stampholder"

      Operation.new(
        id: data[:id],
        alloys: data[:alloys],
        process_type: 'standard_anodising',
        anodic_classes: data[:anodic_classes],
        target_thickness: data[:target_thickness],
        vat_numbers: data[:vat_numbers],
        operation_text: operation_text,
        ocv: ocv_spec(data[:operation_text], aerospace_defense)
      )
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
