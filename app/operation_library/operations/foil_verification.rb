# app/operation_library/operations/foil_verification.rb
module OperationLibrary
  class FoilVerification
    # Calibrated foil sets per Elcometer, as verified against the certs.
    # UPDATE THIS TABLE whenever a meter or foil is recalibrated, replaced
    # or retired - it feeds the paperless dropdown suggestions.
    # Values are µm, stored as the strings an operator would type.
    FOIL_METERS = {
      "5"  => ["23.8", "79.8", "49.4"],
      "8"  => ["24.5", "49.3"],
      "9"  => ["23.3", "50.4", "79.3"],
      "10" => ["12.2", "12.2"]
    }.freeze

    # Dropdown suggestions for the paperless OCV fields (consumed by the
    # ocv_suggestions view helper). Meter numbers as-is; foil values pooled
    # across meters, deduped, ascending - the typing filter narrows them.
    def self.meter_suggestions
      FOIL_METERS.keys
    end

    def self.foil_value_suggestions
      FOIL_METERS.values.flatten.uniq.sort_by(&:to_f)
    end

    # Advisory window offered around each calibrated foil value for the
    # measured-reading dropdowns (±5%, five points per foil). Purely a
    # typing aid - a reading outside this spread is exactly the one that
    # must be typed and investigated, and the datalist never prevents that.
    MEASURED_WINDOW = 0.05

    def self.measured_thickness_suggestions
      FOIL_METERS.values.flatten.map(&:to_f).uniq.flat_map { |v|
        [-MEASURED_WINDOW, -MEASURED_WINDOW / 2, 0.0,
         MEASURED_WINDOW / 2, MEASURED_WINDOW].map { |f| v * (1 + f) }
      }.sort.map { |v| sig3(v) }.uniq
    end

    # Format to 3 significant figures (12.2, 49.4, 105)
    def self.sig3(value)
      decimals = 2 - Math.log10(value.abs).floor
      format("%.#{[decimals, 0].max}f", value)
    end

    # Explicit OCV spec - field names deliberately identical to the
    # /foil verification|elcometer/ fallback in OcvSpecs, so copied/manual
    # foil ops record the same shape as library ones (see the ALIGN THESE
    # note in ocv_specs.rb).
    #
    # elcometer_readings is the batch's film thickness set, recorded here
    # in-line (paperless) rather than on the release note: a JSON array of
    # readings, or the NADCAP sample-plan blob on PRF/Type III work. Rules
    # and shape live in FilmThickness; the release note snapshots it for
    # the CofC.
    def self.ocv_spec
      OcvSpecs.fields(
        :meter_no,
        :foil_value_1, :measured_thickness_1,
        :foil_value_2, :measured_thickness_2,
        FilmThickness::ANODIC_FIELD.to_sym,
        basis: :nadcap
      )
    end

    def self.operations
      [
        Operation.new(
          id: 'FOIL_VERIFICATION',
          process_type: 'verification',
          operation_text: operation_text,
          ocv: ocv_spec
        )
      ]
    end

    # Check if foil verification is required for a specific treatment (aerospace/defense + anodising)
    def self.foil_verification_required_for_treatment?(treatment_type, aerospace_defense: false)
      return false unless aerospace_defense
      anodising_treatments = ['standard_anodising', 'hard_anodising', 'chromic_anodising']
      anodising_treatments.include?(treatment_type)
    end

    # Get a foil verification operation for a specific treatment
    def self.get_foil_verification_operation_for_treatment(treatment_type, treatment_index = nil)
      Operation.new(
        id: "FOIL_VERIFICATION_#{treatment_type.upcase}#{treatment_index ? "_#{treatment_index}" : ""}",
        process_type: 'verification',
        operation_text: operation_text,
        ocv: ocv_spec
      )
    end

    # Insert foil verification for a specific treatment at the beginning of that treatment cycle
    def self.insert_foil_verification_for_treatment(operations_sequence, treatment_type, treatment_index = nil, aerospace_defense: false)
      return operations_sequence unless foil_verification_required_for_treatment?(treatment_type, aerospace_defense: aerospace_defense)

      # Get the treatment-specific foil verification operation
      foil_verification_op = get_foil_verification_operation_for_treatment(treatment_type, treatment_index)

      # Insert at the beginning of the operations sequence (this will be called per-treatment)
      [foil_verification_op] + operations_sequence
    end

    private

    # Instruction only - the capture shape lives in the OCV spec.
    # (The old baked-in "Batch 1: Meter no:___ ..." blank lines were the
    # paper recording mechanism; blanks are the renderer's job now.)
    def self.operation_text
      "**Elcometer foil verification** (Aerospace/Defense requirement)"
    end
  end
end
