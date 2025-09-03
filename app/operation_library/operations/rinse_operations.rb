# app/operation_library/operations/rinse_operations.rb
module OperationLibrary
  class RinseOperations
    # Define which process types are non-water chemical processes that require rinses
    NON_WATER_CHEMICAL_PROCESSES = %w[
      degrease
      pretreatment
      enp_pretreatment
      chemical_conversion
      standard_anodising
      hard_anodising
      chromic_anodising
      etch
      electroless_nickel_plating
      sealing
      dichromate_sealing
      stripping
      stripping_only
      dye
    ].freeze

    # Define which process types are extreme pH processes WITHOUT sulphates
    EXTREME_PH_SANS_SULPHATES_PROCESSES = %w[
      pretreatment
      etch
      chromic_anodising
      dichromate_sealing
      stripping
      stripping_only
    ].freeze

    # Define which process types are extreme pH processes WITH sulphates (requiring 5-minute wait)
    EXTREME_PH_WITH_SULPHATES_PROCESSES = %w[
      standard_anodising
      hard_anodising
    ].freeze

    def self.operations
      [
        # Basic rinse - default for most processes
        Operation.new(
          id: 'RINSE',
          process_type: 'rinse',
          operation_text: 'Rinse in clean swill'
        ),

        # Cascade rinse - for extreme pH processes without sulphates (neutralizing + clean swill)
        Operation.new(
          id: 'CASCADE_RINSE',
          process_type: 'rinse',
          operation_text: 'Cascade rinse - neutralizing swill then clean swill'
        ),

        # Cascade rinse with bung removal - for extreme pH processes without sulphates with bungs
        Operation.new(
          id: 'CASCADE_RINSE_BUNGS',
          process_type: 'rinse',
          operation_text: 'Cascade rinse - neutralizing swill then clean swill, remove bungs and spray out holes with water'
        ),

        # NEW: Cascade rinse with 5-minute wait - for sulphate-containing processes
        Operation.new(
          id: 'CASCADE_RINSE_5MIN_WAIT',
          process_type: 'rinse',
          operation_text: 'Cascade rinse - neutralizing swill then clean swill with 5 minute immersion'
        ),

        # NEW: Cascade rinse with 5-minute wait and bung removal - for sulphate-containing processes with bungs
        Operation.new(
          id: 'CASCADE_RINSE_5MIN_WAIT_BUNGS',
          process_type: 'rinse',
          operation_text: 'Cascade rinse - neutralizing swill then clean swill with 5 minute immersion, remove bungs and spray out holes with water'
        ),

        # RO rinse - for electroless nickel plating processes
        Operation.new(
          id: 'RO_RINSE',
          process_type: 'rinse',
          operation_text: 'RO swill'
        )
      ]
    end

  # Get the appropriate rinse operation based on the previous operation and PPI context
  def self.get_rinse_operation(previous_operation = nil, ppi_contains_electroless_nickel: false, masking: {})
    return nil unless previous_operation
    return nil if previous_operation.process_type == 'rinse'
    return nil unless operation_requires_rinse?(previous_operation)

    # If PPI contains electroless nickel plating, always use RO rinse
    if ppi_contains_electroless_nickel
      return operations.find { |op| op.id == 'RO_RINSE' }
    end

    # If extreme pH process with sulphates, use cascade rinse with 5-minute wait
    if EXTREME_PH_WITH_SULPHATES_PROCESSES.include?(previous_operation.process_type)
      if bungs_present_in_masking?(masking)
        return operations.find { |op| op.id == 'CASCADE_RINSE_5MIN_WAIT_BUNGS' }
      else
        return operations.find { |op| op.id == 'CASCADE_RINSE_5MIN_WAIT' }
      end
    end

    # If extreme pH process without sulphates, use standard cascade rinse
    # BUT skip bung removal for stripping operations (both regular stripping and strip-only)
    if EXTREME_PH_SANS_SULPHATES_PROCESSES.include?(previous_operation.process_type)
      if bungs_present_in_masking?(masking) && !['stripping', 'stripping_only'].include?(previous_operation.process_type)
        return operations.find { |op| op.id == 'CASCADE_RINSE_BUNGS' }
      else
        return operations.find { |op| op.id == 'CASCADE_RINSE' }
      end
    end

    # Default to basic rinse
    operations.find { |op| op.id == 'RINSE' }
  end

    # Check if an operation requires a rinse after it
    def self.operation_requires_rinse?(operation)
      return false unless operation
      return false if operation.process_type == 'rinse'

      # Only non-water chemical processes require rinses
      NON_WATER_CHEMICAL_PROCESSES.include?(operation.process_type)
    end

    # Check if bungs are present in masking data
    def self.bungs_present_in_masking?(masking)
      return false unless masking.present? && masking.is_a?(Hash)

      # Check if masking is enabled and methods contain bungs
      return false unless masking["enabled"] == true || masking["enabled"] == "true"

      methods = masking["methods"] || {}
      return false unless methods.present?

      # Handle different masking data structures
      if methods.is_a?(Hash)
        methods.keys.any? { |method| method.to_s == 'bungs' }
      elsif methods.is_a?(Array)
        methods.any? { |method| method.to_s == 'bungs' }
      else
        false
      end
    end

    # Get list of non-water chemical process types (for extending as new operations are added)
    def self.non_water_chemical_processes
      NON_WATER_CHEMICAL_PROCESSES
    end

    # Add a new non-water chemical process type (for future extension)
    def self.add_non_water_chemical_process(process_type)
      NON_WATER_CHEMICAL_PROCESSES << process_type unless NON_WATER_CHEMICAL_PROCESSES.include?(process_type)
    end

    # Get list of extreme pH processes with sulphates (for reference)
    def self.extreme_ph_with_sulphates_processes
      EXTREME_PH_WITH_SULPHATES_PROCESSES
    end

    # Get list of extreme pH processes without sulphates (for reference)
    def self.extreme_ph_sans_sulphates_processes
      EXTREME_PH_SANS_SULPHATES_PROCESSES
    end
  end
end
