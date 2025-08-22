# app/operation_library/operations/rinse_operations.rb
module OperationLibrary
  class RinseOperations
    # Define which process types are non-water chemical processes that require rinses
    NON_WATER_CHEMICAL_PROCESSES = %w[
      chemical_conversion
      standard_anodising
      hard_anodising
      chromic_anodising
      etch
      electroless_nickel_plating
    ].freeze

    # Define which process types are extreme pH processes that require cascade rinse (dichromate coming soon!!)
    EXTREME_PH_PROCESSES = %w[
      etch
      standard_anodising
      hard_anodising
      chromic_anodising
    ].freeze

    def self.operations
      [
        # Basic rinse - default for most processes
        Operation.new(
          id: 'RINSE',
          process_type: 'rinse',
          operation_text: 'Rinse in clean swill'
        ),

        # Cascade rinse - for extreme pH processes (neutralizing + clean swill)
        Operation.new(
          id: 'CASCADE_RINSE',
          process_type: 'rinse',
          operation_text: 'Cascade rinse - neutralizing swill then clean swill'
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
    def self.get_rinse_operation(previous_operation = nil, ppi_contains_electroless_nickel: false)
      return nil unless previous_operation
      return nil if previous_operation.process_type == 'rinse' # Don't rinse after rinse
      return nil unless operation_requires_rinse?(previous_operation)

      # If PPI contains electroless nickel plating, always use RO rinse
      if ppi_contains_electroless_nickel
        return operations.find { |op| op.id == 'RO_RINSE' }
      end

      # If extreme pH process, use cascade rinse
      if EXTREME_PH_PROCESSES.include?(previous_operation.process_type)
        return operations.find { |op| op.id == 'CASCADE_RINSE' }
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

    # Get list of non-water chemical process types (for extending as new operations are added)
    def self.non_water_chemical_processes
      NON_WATER_CHEMICAL_PROCESSES
    end

    # Add a new non-water chemical process type (for future extension)
    def self.add_non_water_chemical_process(process_type)
      NON_WATER_CHEMICAL_PROCESSES << process_type unless NON_WATER_CHEMICAL_PROCESSES.include?(process_type)
    end
  end
end
