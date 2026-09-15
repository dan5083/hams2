# app/operation_library/operations/double_and_etch.rb
module OperationLibrary
  # "Double and etch": a short sacrificial anodise (the "double") followed by an
  # E28 etch, run after degrease/stripping and before the DeOx, to open up the
  # surface ahead of the main anodise. Two finishes:
  #   normal - 3 minutes for both the double and the etch (default)
  #   matte  - 5 minutes for both
  #
  # Selection per anodising treatment card:
  #   auto   - normal when the treatment is dyed and the part is NOT
  #            aerospace/defence, otherwise none (resolved in Part)
  #   none   - never
  #   normal - always, 3 min
  #   matte  - always, 5 min
  #
  # Both ops are followed by a plain cascade rinse (see RinseOperations - the
  # double is treated as sulphate-free for rinsing purposes and neither op
  # triggers bung removal).
  class DoubleAndEtch
    FINISHES = [
      { value: 'auto',   label: 'Auto (dyed, non-aerospace)' },
      { value: 'none',   label: 'None' },
      { value: 'normal', label: 'Normal (3 min)' },
      { value: 'matte',  label: 'Matte (5 min)' }
    ].freeze

    DOUBLE_VATS = [1, 2, 3, 5, 6, 9, 12].freeze
    DOUBLE_VOLTAGE = 20

    MINUTES = {
      'normal' => 3,
      'matte' => 5
    }.freeze

    def self.operations(aerospace_defense: false)
      MINUTES.keys.flat_map { |finish| operations_for(finish, aerospace_defense: aerospace_defense) }
    end

    # Ordered pair [double, etch] for a finish, or [] for none/unknown.
    def self.operations_for(finish, aerospace_defense: false)
      minutes = MINUTES[finish.to_s]
      return [] unless minutes

      suffix = "#{minutes}MIN"

      [
        Operation.new(
          id: "DOUBLE_ANODISE_#{suffix}",
          process_type: 'double_anodise',
          vat_numbers: DOUBLE_VATS,
          operation_text: "**Double anodise** at #{DOUBLE_VOLTAGE}V for #{minutes} minutes in vat #{vat_list_text}",
          ocv: (OcvSpecs.time_temp_volts if aerospace_defense)
        ),
        Operation.new(
          id: "DOUBLE_ETCH_#{suffix}",
          process_type: 'double_etch',
          operation_text: "**Etch** in Oxidite E28 at 20-70°C for #{minutes} minutes",
          ocv: (OcvSpecs.time_temp if aerospace_defense)
        )
      ]
    end

    def self.available_finishes
      FINISHES
    end

    # Resolve the card selection to a concrete finish ('normal' / 'matte') or nil.
    def self.resolve_finish(selection, dyed:, aerospace_defense:)
      case selection.to_s
      when 'normal', 'matte'
        selection.to_s
      when 'auto', ''
        (dyed && !aerospace_defense) ? 'normal' : nil
      else
        nil
      end
    end

    def self.vat_list_text
      *head, tail = DOUBLE_VATS
      "#{head.join(', ')} or #{tail}"
    end
  end
end
