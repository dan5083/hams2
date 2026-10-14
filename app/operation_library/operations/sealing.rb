# app/operation_library/operations/sealing.rb
#
# Seal ops carry OcvSpecs.time_temp on aero/defence work; the record lives
# in the spec, not in the text. The old "**OCV Monitoring:**" blank rows
# are stripped from already-stored parts at freeze time by
# OcvSpecs.strip_legacy_blanks, and edited/manual seals resolve the same
# shape through OcvSpecs::FALLBACK_PATTERNS.
module OperationLibrary
  class Sealing
    # id, process_type, form label, base text
    SEALS = [
      ['SODIUM_DICHROMATE_SEAL', 'dichromate_sealing', 'Sodium Dichromate Seal',
       'Seal in sodium dichromate at 93°C - 99°C for 2-3 minutes per μm of Measured Film Thickness (with a maximum of 30 minutes)'],
      ['OXIDITE_SECO_SEAL', 'sealing', 'Oxidite SE-CO Seal',
       'Seal in Oxidite SE-CO at 25-32°C for 0.5-1 minute per μm of Measured Film Thickness (with a maximum of 20 minutes)'],
      ['HOT_WATER_DIP', 'sealing', 'Hot Water Dip',
       'Hot water dip for 15-30 seconds.'],
      ['HOT_SEAL', 'sealing', 'Hot Seal',
       'Seal in hot seal at 96°C for 2-3 minutes per μm of Measured Film Thickness (with a minimum of 10 mins, and a maximum of 40 mins)'],
      ['SURTEC_650V_SEAL', 'sealing', 'SurTec 650V Seal',
       'Seal in SurTec 650V at 28-32°C for 0.5-1 minute per μm of Measured Film Thickness (with a maximum of 20 minutes)'],
      ['DEIONISED_WATER_SEAL', 'sealing', 'Deionised Water Seal',
       'Seal in deionised water at 75-85°C for 4-5 minutes per μm of Measured Film Thickness (in works laboratory)']
    ].freeze

    def self.operations(aerospace_defense: false)
      SEALS.map do |id, process_type, _label, base_text|
        Operation.new(
          id: id,
          process_type: process_type,
          operation_text: build_operation_text(base_text, aerospace_defense),
          ocv: (OcvSpecs.time_temp if aerospace_defense)
        )
      end
    end

    # Get available sealing types for form selection
    def self.available_sealing_types
      SEALS.map { |id, _type, label, _text| { value: id, label: label } }
    end

    # Get specific sealing operation by ID with aerospace flag
    def self.get_sealing_operation(sealing_id, aerospace_defense: false)
      operations(aerospace_defense: aerospace_defense).find { |op| op.id == sealing_id }
    end

    # Aero/defence seals keep the time-range calculation prompt in the text;
    # the time/temp capture itself is the OCV spec.
    def self.build_operation_text(base_text, aerospace_defense)
      return base_text unless aerospace_defense
      "#{base_text}. Please calculate time range and record: _____m to _____m"
    end
    private_class_method :build_operation_text
  end
end
