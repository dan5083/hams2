# app/jobs/po_intake_assistant_job.rb
#
# Stage 2 of intake — same agentic loop and DB guards as the chat assistant,
# but with an intake-only system prompt and one extra tool, record_outcome,
# which writes the structured proposal onto the InboundPurchaseOrder.
#
# The assistant reads the PO, resolves each line to a Part (creating one the
# usual template-clone way when the PO gives enough to go on), then records
# the outcome. A clean proposal — customer unambiguous, every line matched —
# is booked on the spot via InboundPurchaseOrder#create_order!: customer
# order, PO attached, works orders. The human check is Contract Review.
# Anything it can't resolve parks in needs_review with the reason.
class PoIntakeAssistantJob < AiAssistantJob
  RECORD_OUTCOME_TOOL = {
    name: "record_outcome",
    description: <<~DESC,
      Record your reading of this email on the InboundPurchaseOrder. Call this
      exactly once, as your last tool call, then reply with a 2–4 line summary.
      If outcome is "proposal" and every line has part_status "matched", HAMS
      books it immediately: CustomerOrder, PO attached, one WorksOrder per line.
      Otherwise it parks for a person. The tool result tells you which happened.
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

    return { recorded: true, status: status, booked: false } unless bookable?(input)

    begin
      co = @inbound.create_order!(reviewed_by: @request_user)
      { recorded: true, status: "booked", booked: true, customer_order_id: co.id,
        works_orders: co.works_orders.active.map(&:display_name), summary: @inbound.summary }
    rescue => e
      # Booking failed (part config, validation, duplicate...) — keep the
      # proposal, park it with the reason. create_order! is transactional so
      # nothing half-booked is left behind.
      @inbound.update!(status: "needs_review", summary: "Auto-book failed: #{e.message.first(400)}")
      { recorded: true, status: "needs_review", booked: false, error: e.message }
    end
  rescue => e
    { error: e.class.to_s, detail: e.message }
  end

  def bookable?(input)
    return false unless input["outcome"] == "proposal"
    return false if input["customer_id"].blank? || input["po_number"].blank?
    lines = Array(input["lines"])
    lines.any? && lines.all? { |l| l["part_status"] == "matched" && l["part_id"].present? && l["quantity"].to_i.positive? }
  end

  # ── Prompt ─────────────────────────────────────────────────────────────

  def build_system_prompt
    [
      core_identity,
      integrity_rules,
      business_context,
      customer_rules,
      pricing_rules,
      part_creation,
      intake_instructions,
      response_style,
      schema_section
    ].join("\n\n")
  end

  def intake_instructions
    <<~PROMPT
      PURCHASE ORDER INTAKE — UNATTENDED RUN:
      You are processing an email that arrived at orders@ with no human present.
      Read the purchase order, resolve every line to a Part, and call record_outcome.
      If your proposal is clean, HAMS books it in on the spot and the works orders go
      to Contract Review, where a person checks them. That board is the safety net —
      your job is to get a sensible, well-read booking in front of it, not to be
      timid. Park only what you cannot resolve.

      WRITES: The only writes you may make with execute_query are creating Parts
      (Step 5b below) and correcting a part issue as CREATING PARTS describes. Do
      NOT create CustomerOrders or WorksOrders yourself and do not call
      PurchaseOrderService — record_outcome does the booking.

      STEP 1 — Is this actually a PO?
      Acknowledgements of our order confirmations, "please quote", delivery queries,
      drawings with no PO, spam, and internal forwards with no order on them are
      outcome "not_a_po". If the subject or body says "amended", "revised", "cancel"
      or "change", or the PO number already has works orders on it, that is outcome
      "needs_human" with the details in notes — amendments are not booked
      automatically.

      STEP 2 — Identify the customer:
        Organization.where("name ILIKE ?", "%fragment%").where(is_customer: true)
      Also try the sender's email domain against the Organizations you find.
      Not exactly one clean match → outcome "needs_human". Never guess a customer.

      STEP 3 — PO number and date. Usually labelled "PO Number", "Purchase Order
      No.", "Order No.". Order date in ISO format if present.

      STEP 4 — Existing order?
        CustomerOrder.find_by(customer_id: ..., number: ...)
      Exists with po_attached? and works orders → "already_on_file" with
      existing_customer_order_id. Exists with no PO / no works orders → still
      "proposal", with existing_customer_order_id set so it's attached to that
      order rather than duplicated.

      STEP 5 — Lines. For every line item extract part number, issue/revision,
      description, quantity, unit price and any line-level reference (apply the
      LUFTHANSA rules). For each line:
        Part.matching(customer_id: org.id, part_number: "...", part_issue: "...").to_a
      5a. Exactly one enabled part with treatments configured → part_id, "matched".
          If a matched part has each_price and the PO states a different price, put
          both in price_note (the PO price is used; the part's price is updated).
      5b. No part → try to create one the usual way (CREATING PARTS above) IF the
          PO gives you the treatment: a spec on the line ("hard anodise 50µm to
          DEF STAN 03-26", "natural anodise & seal to BS1615 AA10", "Alocrom 1200",
          "ENP 25µm") or a drawing among the attachments. Same part number under
          this customer with a different issue → follow the DUPLICATE PART NUMBERS
          rule rather than creating a second part. After creating, set part_id and
          "matched". If the PO gives you nothing to determine the process from,
          leave it "not_found" and say so in notes — a person will set the part up.
      5c. More than one match → "ambiguous", with the candidates in notes.
      A "proposal" with any line not "matched" parks for review; nothing is booked
      until a person resolves it.

      STEP 6 — Which attachment is the PO? Set po_attachment_index. Drawings and
      T&Cs are noted in notes, not treated as the PO.

      STEP 7 — record_outcome, then a short summary in your final reply: customer,
      PO number, what was booked (or why it parked), and anything the contract
      reviewer should look at. No links needed.
    PROMPT
  end
end
