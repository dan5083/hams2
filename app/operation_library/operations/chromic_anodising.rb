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

    # Minutes into the cycle at which voltage is read, per process. These are
    # the ramp's transition points - the moments where a reading tells you
    # something the neighbouring readings don't. The EXPECTED voltage at each
    # is not repeated here: it is already stated in the operation text's ramp
    # description, which is the one place it should live.
    VOLTAGE_CHECKPOINT_MINUTES = {
      # 40V reached / 40V held / 50V reached / end
      'CAA_40_50V_40MIN' => [10, 30, 35, 40],
      # 22V reached / mid-hold / end
      'CAA_22V_37MIN' => [7, 20, 37]
    }.freeze

    # Any chromic process not listed above (new id, renamed id) still captures
    # a sane three readings rather than dropping to temperature alone.
    DEFAULT_VOLTAGE_CHECKPOINT_MINUTES = [10, 20, 30].freeze

    def self.voltage_checkpoint_minutes(operation_id)
      VOLTAGE_CHECKPOINT_MINUTES.fetch(operation_id, DEFAULT_VOLTAGE_CHECKPOINT_MINUTES)
    end

    # OCV spec. Chromic is a ramped process, so a single voltage box would not
    # describe what happened - the spec names one field per checkpoint and the
    # renderer draws them, on screen or on paper.
    #
    # Measured film thickness is captured on BOTH bases. The operation text
    # tells the operator to check it against specification either way, so
    # there is no reading of this job where the figure isn't taken; the only
    # question is whether it lands somewhere. Aero/defence adds temperature
    # and the voltage trace on top, per IP2007 sequential capture.
    def self.ocv_spec(operation_id, aerospace_defense)
      if aerospace_defense
        volts = voltage_checkpoint_minutes(operation_id).map { |m| :"volts_#{m}min" }
        OcvSpecs.fields(:temp, *volts, :film_thickness, basis: :nadcap)
      else
        OcvSpecs.fields(:film_thickness, basis: :general)
      end
    end

    private

    def self.create_operation(data, aerospace_defense)
      # Operation text carries the process and the instruction, never blanks:
      # what gets recorded is declared by the OCV spec and drawn by the
      # renderer. Aero/defence and commercial read identically here - the
      # difference is in how much the spec captures, not in what the operator
      # is told to do.
      operation_text = data[:operation_text] +
        " -- check film thickness against specification, if out of range inform an A stampholder"

      Operation.new(
        id: data[:id],
        alloys: data[:alloys],
        process_type: 'chromic_anodising',
        anodic_classes: data[:anodic_classes] || [],
        target_thickness: data[:target_thickness] || 0,
        vat_numbers: data[:vat_numbers],
        operation_text: operation_text,
        ocv: ocv_spec(data[:id], aerospace_defense)
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
