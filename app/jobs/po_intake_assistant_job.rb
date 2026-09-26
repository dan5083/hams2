# app/jobs/po_intake_assistant_job.rb
#
# Stage 2 of intake — same agentic loop and DB guards as the chat assistant,
# but with an intake-only system prompt and one extra tool, record_outcome,
# which writes the structured proposal onto the InboundPurchaseOrder.
#
# Review mode: the assistant READS and PROPOSES. It does not create
# CustomerOrders or WorksOrders. A human calls ipo.create_order! (or, later,
# clicks Approve on the review page). When the review flow has proven itself,
# auto-creation is a prompt change plus calling create_order! from
# record_outcome — the plumbing is already in place.
class PoIntakeAssistantJob < AiAssistantJob
  RECORD_OUTCOME_TOOL = {
    name: "record_outcome",
    description: <<~DESC,
      Record your reading of this email on the InboundPurchaseOrder. Call this
      exactly once, as your last tool call, then reply with a 2–4 line summary.
    DESC
    input_schema: {
      type: "object",
      properties: {
        outcome: {
          type: "string",
          enum: %w[proposal already_on_file not_a_po needs_human],
          description: "proposal = a PO you could read; already_on_file = a CustomerOrder with this number already has a PO attached; not_a_po = acknowledgement/query/spam/drawing-only; needs_human = something you couldn't resolve (customer ambiguous, unreadable, amendment to an existing order, etc)"
        },
        customer_id:          { type: "string", description: "Organization id (uuid), if uniquely matched" },
        customer_name:        { type: "string" },
        po_number:            { type: "string" },
        order_date:           { type: "string", description: "ISO 8601 date if on the PO" },
        po_attachment_index:  { type: "integer", description: "Which attachment index is the PO itself (not drawings/T&Cs)" },
        existing_customer_order_id: { type: "string", description: "For already_on_file, or when an order exists without a PO attached" },
        lines: {
          type: "array",
          items: {
            type: "object",
            properties: {
              part_number:        { type: "string" },
              part_issue:         { type: "string" },
              description:        { type: "string" },
              quantity:           { type: "number" },
              unit_price:         { type: "number" },
              customer_reference: { type: "string", description: "Line-level reference, e.g. Lufthansa CS-Order/SerialNo" },
              part_id:            { type: "string", description: "Matching Part id (uuid) in HAMS, if found" },
              part_status:        { type: "string", enum: %w[matched not_found ambiguous], description: "Result of Part.matching for this line" },
              price_note:         { type: "string", description: "e.g. 'PO £4.50 vs HAMS each_price £4.20'" }
            }
          }
        },
        notes: { type: "string", description: "Anything the reviewer should know: mismatches, delivery dates, special instructions, drawings supplied" }
      },
      required: ["outcome"]
    }
  }.freeze

  def perform(request_id, inbound_id)
    @inbound      = InboundPurchaseOrder.find(inbound_id)
    request       = AiAssistantRequest.find(request_id)
    @request_user = request.user
    @request_id   = request_id

    response_text = run_agentic_loop(request.messages)
    request.mark_complete!(response_text)

    # Belt and braces: if the model never called record_outcome, don't leave
    # the row stuck in "analysing".
    if @inbound.reload.status == "analysing"
      @inbound.update!(status: "needs_review",
                       summary: "Assistant finished without recording an outcome. Reply was:\n#{response_text.to_s.first(2000)}")
    end
  rescue => e
    Rails.logger.error "[PoIntakeAssistantJob] #{inbound_id}: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    AiAssistantRequest.find_by(id: request_id)&.mark_error!(e.message)
    @inbound&.update!(status: "error", error: "#{e.class}: #{e.message}")
  end

  private

  def tools
    TOOLS + [RECORD_OUTCOME_TOOL]
  end

  def dispatch_tool(name, input)
    name == "record_outcome" ? record_outcome(input) : super
  end

  def record_outcome(input)
    input   = input.deep_stringify_keys
    outcome = input["outcome"].to_s

    status, summary =
      case outcome
      when "proposal"        then ["needs_review",    "PO #{input['po_number']} from #{input['customer_name']} — #{Array(input['lines']).size} line(s)"]
      when "already_on_file" then ["already_on_file", "PO #{input['po_number']} already attached to CustomerOrder #{input['existing_customer_order_id']}"]
      when "not_a_po"        then ["ignored",         "Not a PO: #{input['notes'].to_s.first(300)}"]
      else                        ["needs_review",    "Needs a human: #{input['notes'].to_s.first(300)}"]
      end

    @inbound.update!(
      status:            status,
      proposal:          input,
      summary:           summary,
      customer_order_id: input["existing_customer_order_id"].presence
    )
    { recorded: true, status: status }
  rescue => e
    { error: e.class.to_s, detail: e.message }
  end

  # ── Prompt ─────────────────────────────────────────────────────────────

  def build_system_prompt
    [
      core_identity,
      integrity_rules,
      business_context,
      customer_rules,
      intake_instructions,
      response_style,
      schema_section
    ].join("\n\n")
  end

  def intake_instructions
    <<~PROMPT
      PURCHASE ORDER INTAKE — UNATTENDED RUN, READ-ONLY:
      You are processing an email that arrived at orders@ with no human present.
      Your job is to READ the purchase order and RECORD a structured proposal via
      the record_outcome tool. You must NOT create, update or delete anything with
      execute_query — no CustomerOrder, no WorksOrder, no Part, no attachment. A
      person will review your proposal and book it in. Read-only queries only.

      STEP 1 — Is this actually a PO?
      Look at the attachments and the email body. Acknowledgements of our order
      confirmations, "please quote", delivery queries, drawings with no PO, spam,
      and internal forwards with no order on them are outcome "not_a_po". If the
      subject or body says "amended", "revised", "cancel" or "change", treat it as
      outcome "needs_human" with the details in notes — amendments to existing
      orders are not booked automatically.

      STEP 2 — Identify the customer:
        Organization.where("name ILIKE ?", "%fragment%").where(is_customer: true)
      Also try the sender's email domain against the Organizations you find.
      If there is not exactly one clean match, outcome "needs_human" — never guess.

      STEP 3 — PO number and date. The PO number is usually labelled "PO Number",
      "Purchase Order No.", "Order No." etc. Take the order date if present, ISO
      format.

      STEP 4 — Existing order?
        CustomerOrder.find_by(customer_id: ..., number: ...)
      If it exists and po_attached? → outcome "already_on_file" with
      existing_customer_order_id. If it exists without a PO attached, still
      outcome "proposal" but set existing_customer_order_id so the reviewer
      attaches to it rather than creating a duplicate.

      STEP 5 — Lines. For every line item extract part number, issue/revision,
      description, quantity, unit price and any line-level reference. For each,
      check:
        Part.matching(customer_id: org.id, part_number: "...", part_issue: "...").to_a
      and set part_id + part_status (matched / not_found / ambiguous). If a
      matched part has each_price and the PO states a different price, put both
      in price_note. Apply the LUFTHANSA rules above when relevant.

      STEP 6 — Which attachment is the PO? Set po_attachment_index. Drawings and
      T&Cs are noted in notes, not treated as the PO.

      STEP 7 — record_outcome, then a short summary in your final reply (customer,
      PO number, line count, and anything the reviewer must look at). No links
      needed; the reviewer has the record open.
    PROMPT
  end
end
