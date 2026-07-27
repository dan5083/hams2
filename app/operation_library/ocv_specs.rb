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
#   basis:    :nadcap  - operation-sequential capture required for
#                        aerospace/defense work (per IP2007)
#             :general - spec/customer quality requirement on any WO
#   batching: :single  - part only ever runs one batch per WO
#                        (omitted = repeatable batches, paper prints 3 rows)
module OperationLibrary
  module OcvSpecs
    # The standard time/temp shape (was copy-pasted into 8 library files)
    def self.time_temp(batching: nil, basis: :nadcap)
      build([:time, :temp], batching: batching, basis: basis)
    end

    # Time/temp/voltage for electrolytic processes (pretreatments electroclean etc.)
    def self.time_temp_volts(batching: nil, basis: :nadcap)
      build([:time, :temp, :volts], batching: batching, basis: basis)
    end

    # One-off field lists (foil verification, test pieces, water break, ...)
    def self.fields(*names, batching: nil, basis: :general)
      build(names, batching: batching, basis: basis)
    end

    def self.build(fields, batching:, basis:)
      spec = { fields: fields, basis: basis }
      spec[:batching] = batching if batching
      spec
    end
    private_class_method :build
  end
end
