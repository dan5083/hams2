# app/operation_library/operations/dye.rb
module OperationLibrary
  class Dye
    def self.operations(aerospace_defense = nil)
      [
        # Black dye operation
        Operation.new(
          id: 'BLACK_DYE',
          process_type: 'dye',
          operation_text: build_dye_text('Black', '25-30', aerospace_defense)
        ),

        # Red dye operation
        Operation.new(
          id: 'RED_DYE',
          process_type: 'dye',
          operation_text: build_dye_text('Red', '15-25', aerospace_defense)
        ),

        # Blue dye operation
        Operation.new(
          id: 'BLUE_DYE',
          process_type: 'dye',
          operation_text: build_dye_text('Blue', '25-30', aerospace_defense)
        ),

        # Gold dye operation
        Operation.new(
          id: 'GOLD_DYE',
          process_type: 'dye',
          operation_text: build_dye_text('Gold', '15-25', aerospace_defense)
        ),

        # Green dye operation
        Operation.new(
          id: 'GREEN_DYE',
          process_type: 'dye',
          operation_text: build_dye_text('Green', '15-25', aerospace_defense)
        )
      ]
    end

    # Get available dye colors for form selection
    def self.available_dye_colors
      [
        { value: 'BLACK_DYE', label: 'Black' },
        { value: 'RED_DYE', label: 'Red' },
        { value: 'BLUE_DYE', label: 'Blue' },
        { value: 'GOLD_DYE', label: 'Gold' },
        { value: 'GREEN_DYE', label: 'Green' }
      ]
    end

    # Get specific dye operation by ID - updated to accept aerospace_defense parameter
    def self.get_dye_operation(dye_id, aerospace_defense: false)
      operations(aerospace_defense).find { |op| op.id == dye_id }
    end

    # Check if dyeing is applicable (only for anodising processes)
    def self.dyeing_applicable?(process_type)
      ['standard_anodising', 'hard_anodising', 'chromic_anodising'].include?(process_type)
    end

    private

    def self.build_dye_text(color, duration, aerospace_defense)
      base_text = "**#{color} dye** for #{duration} minutes"

      # Add time and temperature monitoring for aerospace/defense
      if aerospace_defense
        monitoring = build_time_temp_monitoring_text
        base_text += "\n\n**Monitoring:**\n#{monitoring}"
      end

      base_text
    end

    def self.build_time_temp_monitoring_text
      text_lines = []
      (1..3).each do |batch|
        text_lines << "Batch ___: Time ___    Temp ___°C"
      end
      text_lines.join("\n")
    end
  end
end
