# app/operation_library/operations/contract_review_operations.rb
module OperationLibrary
  class ContractReviewOperations
    def self.operations
      [
        # Universal contract review operation for all PPIs
        Operation.new(
          id: 'CONTRACT_REVIEW',
          process_type: 'contract_review',
          operation_text: 'Contract review - Route card, PO, and drawing to be checked for errors, issues, and incongruencies (by \'A\' Stamp Holder) and contained IAW IP2002'
        )
      ]
    end

    # Contract review is required for all PPIs (always first operation)
    def self.contract_review_required?(operations_sequence)
      # Contract review is always required unless already present
      !operations_sequence.any? { |op| op.process_type == 'contract_review' }
    end

    # Get the contract review operation
    def self.get_contract_review_operation
      operations.first
    end

    # Insert contract review at the very beginning of a sequence
    def self.insert_contract_review_if_required(operations_sequence)
      return operations_sequence unless contract_review_required?(operations_sequence)

      # Insert contract review at the very beginning
      [get_contract_review_operation] + operations_sequence
    end
  end
end
