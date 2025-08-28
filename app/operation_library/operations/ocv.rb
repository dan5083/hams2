# app/operation_library/operations/ocv.rb
module OperationLibrary
  class Ocv
    # Define non-water chemical processes that require OCV monitoring
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
    ].freeze

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
        # For anodising operations, calculate voltage monitoring intervals
        voltage_intervals = calculate_voltage_monitoring_intervals(anodising_operation)

        Operation.new(
          id: base_operation.id,
          process_type: base_operation.process_type,
          operation_text: build_voltage_monitoring_text(voltage_intervals)
        )
      else
        # For non-electrolytic processes, just record time and temp (no voltage)
        Operation.new(
          id: base_operation.id,
          process_type: base_operation.process_type,
          operation_text: "OCV: Batch 1: Time ___m ___s    Temp ___°C\nOCV: Batch 2: Time ___m ___s    Temp ___°C\nOCV: Batch 3: Time ___m ___s    Temp ___°C"
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

    # Calculate voltage monitoring intervals for anodising operations (every 5 minutes)
    def self.calculate_voltage_monitoring_intervals(anodising_operation)
      # Extract time duration from operation text (e.g., "15V-->20V over 2 minutes" -> 2)
      time_match = anodising_operation.operation_text.match(/over (\d+) minutes/)
      total_minutes = time_match ? time_match[1].to_i : 20 # Default to 20 minutes

      # Calculate number of 5-minute intervals
      intervals = (total_minutes / 5.0).ceil

      {
        total_minutes: total_minutes,
        intervals: intervals,
        temperature: calculate_temperature_for_anodising(anodising_operation)
      }
    end

    # Build voltage monitoring text with proper intervals
    def self.build_voltage_monitoring_text(voltage_data)
      intervals = voltage_data[:intervals]

      text_lines = []
      (1..3).each do |batch|
        interval_texts = []
        (1..intervals).each do |interval|
          time_mark = interval * 5
          interval_texts << "#{time_mark}min: ___V"
        end
        text_lines << "OCV: Batch #{batch}: Temp ___°C [#{interval_texts.join(' | ')}]"
      end

      text_lines.join("\n")
    end

    # Calculate appropriate temperature for anodising operation
    def self.calculate_temperature_for_anodising(anodising_operation)
      # Temperature should always be blank for operator to fill in
      "___"
    end

    # Check if operation is a non-water chemical treatment
    def self.non_water_chemical_treatment?(operation)
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
