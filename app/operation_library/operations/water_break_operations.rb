# app/operation_library/operations/water_break_operations.rb
module OperationLibrary
  class WaterBreakOperations
    def self.operations
      [
        # Water break test operation for aerospace/defense applications
        Operation.new(
          id: 'WATER_BREAK_TEST',
          process_type: 'water_break_test',
          operation_text: '**Water-break test** - Check all areas (including holes and jigging locations) for signs of water-breaking after 30 seconds. If fail: repeat degrease once and retest. If 1 failure occurs please record here ____ If fail twice: put works on hold in clean swill and inform company director.'
        )
      ]
    end

    # Water break test is required only for aerospace/defense applications after cleaning
    def self.water_break_test_required?(operations_sequence, aerospace_defense: false)
      return false unless aerospace_defense
      return false if operations_sequence.empty?

      # Check if any cleaning step (degrease or ENP cleaning like Keycote 245) is present
      has_cleaning = operations_sequence.any? { |op| op.cleaning_step? }
      has_cleaning
    end

    # Get the water break test operation
    def self.get_water_break_test_operation
      operations.first
    end

    # Insert water break test immediately after the rinse that follows a cleaning step
    # This now inserts a water break test after EACH cleaning operation (once per cycle)
    def self.insert_water_break_test_if_required(operations_sequence, aerospace_defense: false)
      return operations_sequence unless water_break_test_required?(operations_sequence, aerospace_defense: aerospace_defense)

      # Find all cleaning operation indices (degrease and ENP cleaning steps like Keycote 245)
      cleaning_indices = []
      operations_sequence.each_with_index do |op, index|
        cleaning_indices << index if op.cleaning_step?
      end

      return operations_sequence if cleaning_indices.empty?

      # Work backwards through the cleaning operations so that inserting operations
      # doesn't affect the indices of earlier operations
      new_sequence = operations_sequence.dup

      cleaning_indices.reverse.each do |cleaning_index|
        # Find the rinse operation that follows this cleaning step
        rinse_after_cleaning_index = nil
        (cleaning_index + 1).upto(new_sequence.length - 1) do |i|
          operation = new_sequence[i]
          if operation && operation.process_type == 'rinse'
            rinse_after_cleaning_index = i
            break
          end
        end

        # Insert water break test after the rinse (or after cleaning step if no rinse found)
        insertion_index = rinse_after_cleaning_index || cleaning_index
        new_sequence.insert(insertion_index + 1, get_water_break_test_operation)
      end

      new_sequence
    end
  end
end
