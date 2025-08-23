# app/operation_library/operations/masking.rb
module OperationLibrary
  class Masking
    # Available masking methods
    MASKING_METHODS = [
      { value: 'bungs', label: 'Bungs' },
      { value: 'pc21_polyester_tape', label: 'PC21 - Polyester tape' },
      { value: '45_stopping_off_lacquer', label: '45 Stopping off lacquer' }
    ].freeze

    def self.operations(selected_methods = {})
      [
        Operation.new(
          id: 'MASKING',
          process_type: 'masking',
          operation_text: build_masking_text(selected_methods)
        )
      ]
    end

    # Get available masking methods for form selection
    def self.available_methods
      MASKING_METHODS
    end

    # Build the operation text based on selected methods and locations
    def self.build_masking_text(selected_methods = {})
      return 'Mask as specified' if selected_methods.empty?

      masking_instructions = []

      selected_methods.each do |method, location|
        method_name = case method
        when 'bungs'
          'bungs'
        when 'pc21_polyester_tape'
          'PC21 - Polyester tape'
        when '45_stopping_off_lacquer'
          '45 Stopping off lacquer'
        else
          method.humanize.downcase
        end

        if location.present?
          masking_instructions << "mask #{location} with #{method_name}"
        else
          masking_instructions << "mask with #{method_name}"
        end
      end

      # Capitalize first instruction and join with 'and'
      if masking_instructions.length == 1
        masking_instructions.first.capitalize
      else
        first_instruction = masking_instructions.first.capitalize
        remaining_instructions = masking_instructions[1..-1]
        "#{first_instruction} and #{remaining_instructions.join(' and ')}"
      end
    end

    # Get the masking operation with interpolated text
    def self.get_masking_operation(selected_methods = {})
      operations(selected_methods).first
    end

    # Check if any masking methods are selected
    def self.masking_selected?(masking_data)
      masking_data.is_a?(Hash) && masking_data.any? { |method, location| method.present? }
    end
  end
end
