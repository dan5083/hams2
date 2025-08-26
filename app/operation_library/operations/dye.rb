# app/operation_library/operations/dye.rb
module OperationLibrary
  class Dye
    def self.operations
      [
        # Black dye operation
        Operation.new(
          id: 'BLACK_DYE',
          process_type: 'dye',
          operation_text: '**Black dye** for 25-30 minutes'
        ),

        # Red dye operation
        Operation.new(
          id: 'RED_DYE',
          process_type: 'dye',
          operation_text: '**Red dye** for 15-25 minutes'
        ),

        # Blue dye operation
        Operation.new(
          id: 'BLUE_DYE',
          process_type: 'dye',
          operation_text: '**Blue dye** for 25-30 minutes'
        ),

        # Gold dye operation
        Operation.new(
          id: 'GOLD_DYE',
          process_type: 'dye',
          operation_text: '**Gold dye** for 15-25 minutes'
        ),

        # Green dye operation
        Operation.new(
          id: 'GREEN_DYE',
          process_type: 'dye',
          operation_text: '**Green dye** for 15-25 minutes'
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

    # Get specific dye operation by ID
    def self.get_dye_operation(dye_id)
      operations.find { |op| op.id == dye_id }
    end

    # Check if dyeing is applicable (only for anodising processes)
    def self.dyeing_applicable?(process_type)
      ['standard_anodising', 'hard_anodising', 'chromic_anodising'].include?(process_type)
    end
  end
end
