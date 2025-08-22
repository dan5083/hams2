# app/operation_library/operations/degrease_operations.rb
module OperationLibrary
  class DegreaseOperations
    def self.operations
      [
        # Universal degreasing operation for all materials and processes
        Operation.new(
          id: 'OXIDITE_C8_DEGREASE',
          process_type: 'degrease',
          operation_text: 'Clean in Oxidite C-8 at 65-70°C for 5-10 mins',
          time: 7
        )
      ]
    end

    # Check if degreasing is required (first main process in sequence)
    def self.degreasing_required?(operations_sequence)
      return false if operations_sequence.empty?

      # Get the first non-rinse operation
      first_main_operation = operations_sequence.find { |op| op.process_type != 'rinse' }
      return false unless first_main_operation

      # Degreasing is required if the first main operation is any of these surface treatments
      surface_treatment_processes = %w[
        standard_anodising
        hard_anodising
        chromic_anodising
        chemical_conversion
        electroless_nickel_plating
      ]

      surface_treatment_processes.include?(first_main_operation.process_type)
    end

    # Get the degreasing operation
    def self.get_degrease_operation
      operations.first
    end

    # Insert degreasing at the beginning of a sequence if required
    def self.insert_degrease_if_required(operations_sequence)
      return operations_sequence unless degreasing_required?(operations_sequence)

      # Check if degreasing is already present
      has_degrease = operations_sequence.any? { |op| op.process_type == 'degrease' }
      return operations_sequence if has_degrease

      # Insert degreasing at the beginning
      [get_degrease_operation] + operations_sequence
    end
  end
end
