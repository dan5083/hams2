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
    def self.insert_water_break_test_if_required(operations_sequence, aerospace_defense: false)
      return operations_sequence unless water_break_test_required?(operations_sequence, aerospace_defense: aerospace_defense)

      # Check if water break test is already present
      has_water_break_test = operations_sequence.any? { |op| op.process_type == 'water_break_test' }
      return operations_sequence if has_water_break_test

      # Find the position of degrease operation
      degrease_index = operations_sequence.find_index { |op| op.process_type == 'degrease' }
      return operations_sequence unless degrease_index

      # Find the rinse operation that follows degrease
      rinse_after_degrease_index = nil
      (degrease_index + 1).upto(operations_sequence.length - 1) do |i|
        operation = operations_sequence[i]
        if operation && operation.process_type == 'rinse'
          rinse_after_degrease_index = i
          break
        end
      end

      # Insert water break test after the rinse (or after degrease if no rinse found)
      insertion_index = rinse_after_degrease_index || degrease_index
      operations_sequence.dup.tap do |seq|
        seq.insert(insertion_index + 1, get_water_break_test_operation)
      end
    end
  end
end
