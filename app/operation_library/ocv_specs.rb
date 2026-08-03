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

    # One-off field lists (foil verification, test pieces, water break, ...)
    def self.fields(*names, batching: nil, basis: :general, **rules)
      build(names, batching: batching, basis: basis, **rules)
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
