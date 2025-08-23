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
        ),

        # Masking removal operation - auto-inserted after unjig
        Operation.new(
          id: 'MASKING_REMOVAL',
          process_type: 'masking_removal',
          operation_text: 'Peel off masking (where possible); dissolve remaining lacquer in ULTRALAC REDUCER. Remove residue with MEK.'
        ),

        # Masking removal check - auto-inserted after masking removal
        Operation.new(
          id: 'MASKING_REMOVAL_CHECK',
          process_type: 'masking_removal_check',
          operation_text: 'Masking removal check - ensure all masking material and residue has been completely removed. Check for any lacquer or adhesive residue on part surfaces.'
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

    # Check if masking removal is required (tape/lacquer only, not bungs)
    def self.masking_removal_required?(selected_operations, masking_methods)
      return false unless selected_operations.include?('MASKING')

      removable_methods = ['pc21_polyester_tape', '45_stopping_off_lacquer']
      masking_methods.keys.any? { |method| removable_methods.include?(method) }
    end

    # Get the operations for masking removal
    def self.get_masking_removal_operations
      operations.select { |op| ['MASKING_REMOVAL', 'MASKING_REMOVAL_CHECK'].include?(op.id) }
    end


  end
end
