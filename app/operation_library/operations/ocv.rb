# app/operation_library/operations/ocv.rb
module OperationLibrary
  class Ocv
    def self.operations
      [
        # Basic OCV operation with templated timing for 3 batches
        Operation.new(
          id: 'OCV_CHECK',
          process_type: 'ocv',
          operation_text: 'OCV: Batch 1: Time {TIME}m {SECONDS}s    Temp {TEMP}°C\nOCV: Batch 2: Time {TIME}m {SECONDS}s    Temp {TEMP}°C\nOCV: Batch 3: Time {TIME}m {SECONDS}s    Temp {TEMP}°C'
        )
      ]
    end

    # Check if OCV is required after a chemical treatment rinse
    def self.ocv_required?(previous_operation, aerospace_defense: false)
      return false unless previous_operation
      return false unless previous_operation.process_type == 'rinse'

      # OCV is required for aerospace/defense applications after rinses that follow non-water chemical treatments
      aerospace_defense && non_water_chemical_treatment_rinse?(previous_operation)
    end

    # Get OCV operation with calculated timing based on the preceding anodising operation
    def self.get_ocv_operation(anodising_operation = nil, aerospace_defense: false)
      return nil unless aerospace_defense

      base_operation = operations.first

      if anodising_operation && is_anodising_operation?(anodising_operation)
        time_data = calculate_ocv_timing(anodising_operation)

        Operation.new(
          id: base_operation.id,
          process_type: base_operation.process_type,
          operation_text: base_operation.operation_text
            .gsub('{TIME}', time_data[:minutes].to_s)
            .gsub('{SECONDS}', time_data[:seconds].to_s)
            .gsub('{TEMP}', time_data[:temperature].to_s)
        )
      else
        # Default OCV operation for non-anodising processes
        Operation.new(
          id: base_operation.id,
          process_type: base_operation.process_type,
          operation_text: base_operation.operation_text
            .gsub('{TIME}', '5')
            .gsub('{SECONDS}', '0')
            .gsub('{TEMP}', '20')
        )
      end
    end

    # Insert OCV operations after rinses that follow non-water chemical treatments
    def self.insert_ocv_if_required(operations_sequence, aerospace_defense: false)
      return operations_sequence unless aerospace_defense

      new_sequence = []

      operations_sequence.each_with_index do |operation, index|
        new_sequence << operation

        # Check if this is a rinse after a non-water chemical treatment
        if operation.process_type == 'rinse' && index > 0
          previous_operation = operations_sequence[index - 1]

          if non_water_chemical_treatment?(previous_operation)
            # Find the most recent anodising operation for timing calculation
            anodising_op = find_most_recent_anodising_operation(operations_sequence, index)
            ocv_operation = get_ocv_operation(anodising_op, aerospace_defense: aerospace_defense)
            new_sequence << ocv_operation if ocv_operation
          end
        end
      end

      new_sequence
    end

    private

    # Calculate OCV timing based on anodising operation thickness
    def self.calculate_ocv_timing(anodising_operation)
      thickness = anodising_operation.target_thickness || 0

      # Calculate 5-minute increments based on thickness
      base_increments = (thickness / 5.0).ceil
      base_minutes = base_increments * 5

      # Add some variation based on operation type
      case anodising_operation.process_type
      when 'hard_anodising'
        # Hard anodising requires longer OCV monitoring
        minutes = base_minutes + 5
        seconds = 30
        temperature = 25
      when 'chromic_anodising'
        # Chromic anodising uses different timing
        minutes = [base_minutes, 10].max # Minimum 10 minutes
        seconds = 0
        temperature = 22
      else # standard_anodising
        minutes = base_minutes
        seconds = 0
        temperature = 20
      end

      {
        minutes: minutes,
        seconds: seconds,
        temperature: temperature
      }
    end

    # Check if operation is a non-water chemical treatment
    def self.non_water_chemical_treatment?(operation)
      NON_WATER_CHEMICAL_PROCESSES = %w[
        degrease
        pretreatment
        enp_pretreatment
        chemical_conversion
        standard_anodising
        hard_anodising
        chromic_anodising
        electroless_nickel_plating
        sealing
        dichromate_sealing
        stripping
        dye
      ]

      NON_WATER_CHEMICAL_PROCESSES.include?(operation.process_type)
    end

    # Check if this rinse follows a non-water chemical treatment
    def self.non_water_chemical_treatment_rinse?(rinse_operation)
      # This would need context from the operations sequence to determine
      # what the rinse is following - handled in the insert method
      true
    end

    # Check if operation is an anodising process
    def self.is_anodising_operation?(operation)
      ['standard_anodising', 'hard_anodising', 'chromic_anodising'].include?(operation.process_type)
    end

    # Find the most recent anodising operation in the sequence before the given index
    def self.find_most_recent_anodising_operation(operations_sequence, current_index)
      (current_index - 1).downto(0) do |i|
        operation = operations_sequence[i]
        return operation if is_anodising_operation?(operation)
      end
      nil
    end
  end
end
