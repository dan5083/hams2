# app/operation_library/operations/contract_review_operations.rb
module OperationLibrary
  class ContractReviewOperations
    FORM = "2002/1"
    ISSUE = "14"  # bump when the checklist below changes; the show page flags
                  # WOs whose answers were recorded against an older issue

    # Form 2002/1 Iss.14 - Aerospace/Defence Contract Review Checklist.
    # Digitised: each item is answered YES/NO with an optional action/comment.
    # scope decides part memory:
    #   part  - the answer is a property of the part; once reviewed it is
    #           remembered on the part and pre-filled on subsequent WOs
    #   order - the answer is specific to this order; asked fresh every time
    CHECKLIST = [
      { "id" => "receipt_of_order",       "scope" => "order", "text" => "Receipt of order - check all details are clear and unambiguous" },
      { "id" => "order_agrees_quotation", "scope" => "order", "text" => "Order agrees with quotation?" },
      { "id" => "specs_at_correct_issue", "scope" => "part",  "text" => "Ensure drawings and relevant specifications have been reviewed and are at the correct issue. Ensure all specifications and quality requirements called out on customer PO are held either electronically or on file and the requirements flow down to the relevant job card and buy off sheet where required",
        "guidance" => "If the correct specification issues are not available, put work on hold and contact the customer. If Terms and Conditions or Quality Requirements are not on file, put work on hold and contact the customer. The operator / chemist should be in no doubt as to the requirements for lot testing / periodic testing once the CR has been carried out" },
      { "id" => "key_characteristics",    "scope" => "part",  "text" => "Have key characteristics been identified on the drawing or as part of this review? (If yes, Phil to determine if control plan required. Refer IP2007 page 7 to determine relevant OCV data to be recorded)" },
      { "id" => "jigging_review",         "scope" => "part",  "text" => "Jigging review - when viewing drawing, carry out a jigging review to ensure work holding, special threads, and component orientation suitable to minimise air locks is taken into account" },
      { "id" => "frozen_planning",        "scope" => "part",  "text" => "Do customer quality stipulations require frozen planning / quality plans?" },
      { "id" => "exceptional_risks",      "scope" => "part",  "text" => "Any identified exceptional risks (masking / alloy etc)?" },
      { "id" => "delivery_achievable",    "scope" => "order", "text" => "Are delivery timescales achievable?" },
      { "id" => "inspection_equipment",   "scope" => "part",  "text" => "Inspection requirements identified; inspection/test equipment available and within calibration" },
      { "id" => "release_certification",  "scope" => "part",  "text" => "Release certification determined" },
      { "id" => "thickness_verification", "scope" => "part",  "text" => "Is coating thickness verification possible?" },
      { "id" => "test_piece",             "scope" => "part",  "text" => "Test piece required",
        "guidance" => "Customer Own / In House (state which in the comment)" },
      { "id" => "tooling_capable",        "scope" => "part",  "text" => "Tooling and production equipment capable and available" },
      { "id" => "materials_available",    "scope" => "order", "text" => "Processing materials to required specification available to meet the delivery programme" },
      { "id" => "production_permit",      "scope" => "order", "text" => "Is a Production Permit required?" },
      { "id" => "hastl_approval",         "scope" => "part",  "text" => "Does HASTL have the appropriate approval to process the order?" },
      { "id" => "calibrated_timers",      "scope" => "part",  "text" => "For timed processes, ensure the works order refers to use of calibrated timers" }
    ].freeze

    def self.operations(aerospace_defense: false)
      # The spec carries a MARKER, not the items. Parts (locked or live)
      # reference the form; the current CHECKLIST is resolved at render time,
      # so a new form issue reaches every part on deploy. The full items are
      # embedded only into the works order's frozen record at first sign-off -
      # the one place a verbatim copy is the point.
      ocv_spec = if aerospace_defense
        { "checklist" => true, "basis" => "nadcap" }
      end

      [
        # Universal contract review operation for all PPIs
        Operation.new(
          id: 'CONTRACT_REVIEW',
          process_type: 'contract_review',
          operation_text: 'Contract review - Route card, PO, and drawing to be checked for errors, issues, and incongruencies (by \'A\' Stamp Holder) and contained IAW IP2002',
          ocv: ocv_spec
        )
      ]
    end

    # Resolve checklist content: the current form for a marker (true), or the
    # embedded array from an older lock / frozen WO record verbatim.
    def self.resolve_checklist(spec_value)
      spec_value == true ? CHECKLIST.map(&:dup) : Array(spec_value)
    end

    # Contract review is required for all PPIs (always first operation)
    def self.contract_review_required?(operations_sequence)
      # Contract review is always required unless already present
      !operations_sequence.any? { |op| op.process_type == 'contract_review' }
    end

    # Get the contract review operation
    def self.get_contract_review_operation(aerospace_defense: false)
      operations(aerospace_defense: aerospace_defense).first
    end

    # Insert contract review at the very beginning of a sequence
    def self.insert_contract_review_if_required(operations_sequence, aerospace_defense: false)
      return operations_sequence unless contract_review_required?(operations_sequence)

      # Insert contract review at the very beginning
      [get_contract_review_operation(aerospace_defense: aerospace_defense)] + operations_sequence
    end
  end
end
