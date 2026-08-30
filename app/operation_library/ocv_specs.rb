# app/operation_library/ocv_specs.rb
#
# Shared OCV (Operator Controlled Variable) spec shapes.
#
# An OCV spec is plain data attached to an Operation. It declares WHAT gets
# recorded, per batch, for that operation. It contains no text and no blanks:
# rendering (paper blanks vs. screen inputs) is the renderer's job, and the
# recorded values live per-WO in customised_process_data.
#
# Keys:
#   fields:   ordered symbols naming the values captured per batch
#   optional: fields that never block a sign-off (recorded if the operator has
#             something to record, absent otherwise)
#   required_if: { field => { other_field => value_or_values } } - the field is
#             required only when the row reads that way. Comparison is
#             case-insensitive on the stripped value.
#   blank_as: { field => "..." } - a field left empty is stamped with this
#             value at sign-off, so the frozen record states the absence
#             instead of carrying an empty box that reads as unfinished
#   basis:    :nadcap  - operation-sequential capture required for
#                        aerospace/defense work (per IP2007)
#             :general - spec/customer quality requirement on any WO
#   batching: :single  - part only ever runs one batch per WO
#                        (omitted = repeatable batches, paper prints 3 rows)
module OperationLibrary
  module OcvSpecs
    # The standard time/temp shape (was copy-pasted into 8 library files)
    def self.time_temp(batching: nil, basis: :nadcap, **rules)
      build([:time, :temp], batching: batching, basis: basis, **rules)
    end

    # Time/temp/voltage for electrolytic processes (pretreatments electroclean etc.)
    def self.time_temp_volts(batching: nil, basis: :nadcap, **rules)
      build([:time, :temp, :volts], batching: batching, basis: basis, **rules)
    end

    # Hard/standard anodise ramp: temp, a voltage reading every 5 minutes for
    # the length of the cycle (the shape the old baked-in "OCV Monitoring"
    # text blocks drew as blanks), and measured film thickness. The library
    # derives total_minutes from the op text's "over N minutes"; anything
    # unparseable captures a 20-minute trace rather than nothing.
    def self.anodise_ramp(total_minutes, batching: nil, basis: :nadcap, **rules)
      checkpoints = (1..(total_minutes / 5.0).ceil).map { |i| :"volts_#{i * 5}min" }
      build([:temp, *checkpoints, :film_thickness], batching: batching, basis: basis, **rules)
    end

    # ENP plating cycle on aero/defence work: time/temp plus the in-line
    # film thickness record (six micrometer points, start/finish either side
    # of the cycle - the op stays open across the whole plating cycle, so
    # the row is editable exactly when both readings are taken).
    def self.enp_plate(batching: nil, basis: :nadcap, **rules)
      build([:time, :temp, FilmThickness::ENP_FIELD.to_sym], batching: batching, basis: basis, **rules)
    end

    # One-off field lists (foil verification, test pieces, water break, ...)
    def self.fields(*names, batching: nil, basis: :general, **rules)
      build(names, batching: batching, basis: basis, **rules)
    end

    # Pattern fallback for aero/defence ops that carry no explicit spec, so
    # renamed library ids and custom static ops still capture OCV rather than
    # silently going record-less. Matched against the op's id and wording.
    # Only ever consulted when the op has no spec of its own - an explicit
    # spec (including a deliberate nil-field one) always wins upstream.
    #
    # Order matters: specific process patterns first, the generic
    # "*OCV monitoring*" marker last - the marker states that capture is
    # required without saying what shape, so it takes the standard time/temp
    # unless a more specific pattern already answered.
    FALLBACK_PATTERNS = [
      [/heat[\s_-]?treat|bake/i, -> { time_temp }],
      # Mirrors AnodisingChromic's DEFAULT_VOLTAGE_CHECKPOINT_MINUTES and its
      # field vocabulary (volts_Nmin), so a copied/manual chromic op records
      # the same shape a library one would. (PG1 froze before this rename
      # with v_Nmin field names - historical, correct for its day.)
      [/chromic\s+acid\s+anodise/i, -> {
        fields(:temp, :volts_10min, :volts_20min, :volts_30min, :film_thickness, basis: :nadcap)
      }],
      [/hard\s+anodise|standard\s+anodise|sulphuric\s+anodise/i, -> { anodise_ramp(20) }],
      # Copied/manual water break and foil verification ops lost their library
      # specs; mirror the shapes the library versions carry. ALIGN THESE with
      # the explicit specs in WaterBreakOperations / the inspection library if
      # they differ - two shapes for one physical test is worse than none.
      [/water[\s-]?break/i, -> {
        fields(:result, :first_failure, basis: :nadcap,
               required_if: { first_failure: { result: "FAIL" } },
               blank_as: { first_failure: "None" })
      }],
      [/foil\s+verification|elcometer/i, -> {
        fields(:meter_no, :foil_value_1, :measured_thickness_1,
               :foil_value_2, :measured_thickness_2,
               FilmThickness::ANODIC_FIELD.to_sym, basis: :nadcap)
      }],
      # ENP ops on aero work carry the six-point micrometer growth record
      # (FilmThickness::ENP_FIELD) alongside time/temp - see
      # ElectrolessNickelPlate.operations. Matched on the library ids and
      # the bath names so a copied ENP op keeps the same shape.
      [/electroless\s+nickel\s+plat|vandalloy|nicklad/i, -> { enp_plate }],
      [/OCV\s+monitoring/i, -> { time_temp }]
    ].freeze

    # Commercial (non-aero) stored ops get the same capture the library gives
    # commercial parts: film thickness only, :general basis. The full traces
    # above stay aero-gated - IP2007 sequential capture is an aero/defence
    # requirement - but the thickness figure is taken on every anodising job,
    # and a spec is the only way it lands anywhere now the paper blank is gone.
    COMMERCIAL_FALLBACK_PATTERNS = [
      [/hard\s+anodise|standard\s+anodise|sulphuric\s+anodise|chromic\s+acid\s+anodise/i, -> {
        fields(:film_thickness, basis: :general)
      }]
    ].freeze

    def self.fallback_for(id, text = nil, aerospace_defense: false)
      haystack = "#{id} #{text}"
      patterns = aerospace_defense ? FALLBACK_PATTERNS : COMMERCIAL_FALLBACK_PATTERNS
      patterns.each do |pattern, spec|
        return spec.call if haystack.match?(pattern)
      end
      nil
    end

    def self.build(fields, batching:, basis:, optional: nil, required_if: nil, blank_as: nil)
      spec = { fields: fields, basis: basis }
      spec[:batching] = batching if batching
      spec[:optional] = Array(optional) if optional.present?
      spec[:required_if] = required_if if required_if.present?
      spec[:blank_as] = blank_as if blank_as.present?
      spec
    end
    private_class_method :build
  end
end
