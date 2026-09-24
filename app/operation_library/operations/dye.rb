# app/operation_library/operations/dye.rb
#
# Dye ops carry NO monitoring text. On aero/defence work the per-batch
# time/temp record is an OCV spec (OcvSpecs.time_temp), rendered by the
# works order as capture fields and required before sign-off. The old
# "**Monitoring:** Batch ___: Time ___ Temp ___°C" block was a paper
# artefact - see OcvSpecs::LEGACY_MONITORING_BLOCK and the
# hams:repair_legacy_dye_ops task for the parts/WOs that still carry it.
module OperationLibrary
  class Dye
    COLOURS = [
      ['BLACK_DYE', 'Black', '25-30'],
      ['RED_DYE',   'Red',   '15-25'],
      ['BLUE_DYE',  'Blue',  '25-30'],
      ['GOLD_DYE',  'Gold',  '15-25'],
      ['GREEN_DYE', 'Green', '15-25']
    ].freeze

    def self.operations(aerospace_defense = nil)
      COLOURS.map do |id, colour, duration|
        Operation.new(
          id: id,
          process_type: 'dye',
          operation_text: "**#{colour} dye** for #{duration} minutes",
          # IP2007 sequential capture is an aero/defence requirement; a
          # commercial dye records nothing, as before.
          ocv: (aerospace_defense ? OcvSpecs.time_temp : nil)
        )
      end
    end

    # Get available dye colors for form selection
    def self.available_dye_colors
      COLOURS.map { |id, colour, _| { value: id, label: colour } }
    end

    def self.get_dye_operation(dye_id, aerospace_defense: false)
      operations(aerospace_defense).find { |op| op.id == dye_id }
    end

    # Check if dyeing is applicable (only for anodising processes)
    def self.dyeing_applicable?(process_type)
      ['standard_anodising', 'hard_anodising', 'chromic_anodising'].include?(process_type)
    end
  end
end
