# app/operation_library/operations/pack_operations.rb
module OperationLibrary
  class PackOperations
    def self.operations
      [
        # Universal pack operation for all PPIs
        Operation.new(
          id: 'PACK',
          process_type: 'pack',
          operation_text: 'Pack: In accordance with IP2011'
        )
      ]
    end

    # Pack is required for all PPIs (always final operation)
    def self.pack_required?(operations_sequence)
      # Pack is always required unless already present
      !operations_sequence.any? { |op| op.process_type == 'pack' }
    end

    # Get the pack operation
    def self.get_pack_operation
      operations.first
    end

    # Insert pack at the very end of a sequence
    def self.insert_pack_if_required(operations_sequence)
      return operations_sequence unless pack_required?(operations_sequence)

      # Insert pack at the very end
      operations_sequence + [get_pack_operation]
    end
  end
end
