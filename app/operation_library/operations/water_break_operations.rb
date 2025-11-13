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

    # Water break test is required only for aerospace/defense applications after degreasing
    def self.water_break_test_required?(operations_sequence, aerospace_defense: false)
      return false unless aerospace_defense
      return false if operations_sequence.empty?

      # Check if degreasing is present in the sequence
      has_degrease = operations_sequence.any? { |op| op.process_type == 'degrease' }
      has_degrease
    end

    # Get the water break test operation
    def self.get_water_break_test_operation
      operations.first
    end

    # Insert water break test immediately after the rinse that follows degreasing
    # This now inserts a water break test after EACH degrease operation (once per cycle)
    def self.insert_water_break_test_if_required(operations_sequence, aerospace_defense: false)
      return operations_sequence unless water_break_test_required?(operations_sequence, aerospace_defense: aerospace_defense)

      # Find all degrease operation indices
      degrease_indices = []
      operations_sequence.each_with_index do |op, index|
        degrease_indices << index if op.process_type == 'degrease'
      end

      return operations_sequence if degrease_indices.empty?

      # Work backwards through the degrease operations so that inserting operations
      # doesn't affect the indices of earlier operations
      new_sequence = operations_sequence.dup

      degrease_indices.reverse.each do |degrease_index|
        # Find the rinse operation that follows this degrease
        rinse_after_degrease_index = nil
        (degrease_index + 1).upto(new_sequence.length - 1) do |i|
          operation = new_sequence[i]
          if operation && operation.process_type == 'rinse'
            rinse_after_degrease_index = i
            break
          end
        end

        # Insert water break test after the rinse (or after degrease if no rinse found)
        insertion_index = rinse_after_degrease_index || degrease_index
        new_sequence.insert(insertion_index + 1, get_water_break_test_operation)
      end

      new_sequence
    end
  end
end
