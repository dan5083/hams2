# app/operation_library/operations/jig_unjig.rb
module OperationLibrary
  class JigUnjig
    # Actual jig types used in the shop
  JIG_TYPES = [
    'a secure titanium-to-part assy',
    'Expanding Jig',
    'Large Aluminum Expanding Jig',
    'Rotor Jig',
    'Vertical AllThread Jig',
    'Twisted Double Strap Jig',
    'Long Twisted Double Strap Jig',
    'Double Strap Jig',
    '3 Prong Jig',
    '4 Prong Jig',
    'Flat 3 Prong Jig',
    'Flat 4 Prong Jig',
    'M6 Jig (Metric)',
    'M6 Jig (UNC)',
    'Thin-stem M8 Jig',
    'Thick-stem M8 Jig',
    'Spring Jig',
    'Circular Spring Jig',
    'Aluminum Clamp Jig',
    'Wheel Nut Jig',
    'Muller Jigs',
    'Flat Piston Jig',
    'Upright Piston Jig',
    'Thick Wrap Around Jig',
    'Thin Wrap Around Jig',
    'Monobloc Jig',
    'Hytorque Jig'
  ].freeze

    def self.operations(jig_type = nil)
      # Use provided jig_type or placeholder for interpolation
      selected_jig = jig_type || '#{jig_type}'

      [
        # Jig operation - auto-inserted before degrease
        Operation.new(
          id: 'JIG_PARTS',
          process_type: 'jig',
          operation_text: "Jig on #{selected_jig} as per WI3601"
        ),

        # Unjig operation - auto-inserted before final inspection
        Operation.new(
          id: 'UNJIG_PARTS',
          process_type: 'unjig',
          operation_text: 'Unjig as per WI3601'
        )
      ]
    end

    # Get available jig types for dropdown
    def self.available_jig_types
      JIG_TYPES
    end

    # Jigging is always required for all processes
    def self.jigging_required?(operations_sequence)
      !operations_sequence.empty?
    end

    # Unjigging is always required when jigging is required
    def self.unjigging_required?(operations_sequence)
      jigging_required?(operations_sequence)
    end

    # Get specific jig operations
    def self.get_jig_operation(jig_type = nil)
      operations(jig_type).find { |op| op.id == 'JIG_PARTS' }
    end

    def self.get_unjig_operation
      operations.find { |op| op.id == 'UNJIG_PARTS' }
    end
  end
end
