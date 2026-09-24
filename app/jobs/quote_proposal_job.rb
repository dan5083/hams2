# app/jobs/quote_proposal_job.rb
#
# "Quote mode" of the HAMS assistant, driven from the quote workbench
# (/quotes/:id/build) rather than the chat widget. Same model, same
# read-only database tool, same rate card and part-template rules — but the
# output is STRUCTURED, not prose: a proposal the workbench renders as an
# editable form (part configuration, price lines, open questions, and the
# reasoning behind each), so nothing is created until a person has read it,
# corrected it and pressed Save.
#
# Runs once on create and again each time answers are posted; the previous
# proposal and the answers go back in as context so it refines rather than
# starts over. Database access is read-only here by construction: writes
# happen in QuoteService.finalise!, from the reviewed form, never from the
# model directly.
class QuoteProposalJob < AiAssistantJob
  PROPOSE_TOOL = {
    name: "propose_quote",
    description: "Submit the finished proposal. Call this exactly once, when the analysis is complete. " \
                 "Everything the workbench shows comes from this call; text outside it is discarded.",
    input_schema: {
      type: "object",
      required: %w[parts lines questions reasoning],
      properties: {
        title:          { type: "string", description: "Short quote title, e.g. 'PD67711-00 — Door Upper Hinge Insert'" },
        summary:        { type: "string", description: "One line: process, spec, thickness. Printed on the quote." },
        enquirer_name:  { type: "string" },
        enquirer_email: { type: "string" },
        notes:          { type: "string", description: "Anything the customer should read on the quote (assumptions, exclusions, lead time)." },
        reasoning:      { type: "string", description: "How you read the drawing/enquiry and why you priced it this way. Plain English, for the person reviewing." },
        parts: {
          type: "array",
          items: {
            type: "object",
            required: %w[key part_number part_issue description process_type treatments reasoning],
            properties: {
              key:              { type: "string", description: "Local id used by lines[].part_key, e.g. 'p1'" },
              existing_part_id: { type: "string", description: "If this part already exists in HAMS for the customer (Part.matching), its id. Then the config fields are informational only." },
              part_number:      { type: "string" },
              part_issue:       { type: "string" },
              description:      { type: "string" },
              specification:    { type: "string" },
              material:         { type: "string" },
              specified_thicknesses: { type: "string" },
              process_type:     { type: "string", description: "anodising | enp | chemical_conversion | ... as Part.process_type uses" },
              aerospace_defense: { type: "boolean" },
              template_part_id: { type: "string", description: "The locked part whose customisation_data you copied the operation set from" },
              treatments:       { type: "array", items: { type: "object" }, description: "operation_selection.treatments exactly as stored on the template, tweaked for this part (type, operation_id, selected_jig_type, selected_alloy, target_thickness, sealing_method, dye_color, masking...)." },
              operation_selection_extra: { type: "object", description: "Other operation_selection keys copied from the template (selected_enp_heat_treatment etc.)" },
              jigging_location: { type: "string", description: "Where/how the part hangs and which surfaces may carry a jig mark. Leave empty if the drawing doesn't say — and ask." },
              jig_type:         { type: "string", description: "Your suggested selected_jig_type, if confident" },
              dimensions_mm:    { type: "object", properties: { l: { type: "number" }, w: { type: "number" }, h: { type: "number" } } },
              surface_area_sqft: { type: "number" },
              reasoning:        { type: "string", description: "Why this configuration: which template, what you changed and why, how you got the area." }
            }
          }
        },
        lines: {
          type: "array",
          items: {
            type: "object",
            required: %w[part_key description quantity unit_amount reasoning],
            properties: {
              part_key:    { type: "string" },
              description: { type: "string" },
              quantity:    { type: "integer" },
              unit_amount: { type: "number", description: "GBP ex VAT per unit (or the MOC as a single line with quantity 1)" },
              reasoning:   { type: "string", description: "rate × sqft, add-ons, MOC comparison — show the arithmetic" }
            }
          }
        },
        questions: {
          type: "array",
          description: "Things you could not settle from the drawing or enquiry. Jigging location and jig type go here when not obvious.",
          items: {
            type: "object",
            required: %w[key question],
            properties: {
              key:              { type: "string" },
              question:         { type: "string" },
              suggested_answer: { type: "string" },
              why:              { type: "string" }
            }
          }
        }
      }
    }
  }.freeze

  def perform(quote_id)
    @quote        = Quote.find(quote_id)
    @request_user = @quote.created_by
    @request_id   = nil
    @proposal     = nil

    run_proposal_loop([{ role: "user", content: user_content }])

    raise "The assistant finished without calling propose_quote" unless @proposal
    @quote.update!(proposal: @proposal, proposal_error: nil, status: "proposed", proposed_at: Time.current)
  rescue => e
    Rails.logger.error "[QuoteProposalJob] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    Quote.find_by(id: quote_id)&.update_columns(proposal_error: e.message, status: "proposal_failed", updated_at: Time.current)
  end

  private

  def tools
    [TOOLS.first, PROPOSE_TOOL]
  end

  def run_proposal_loop(messages)
    loop_messages = messages.dup
    iterations = 0
    @eval_binding = binding

    loop do
      iterations += 1
      raise "Exceeded maximum tool iterations" if iterations > 25

      response = call_anthropic(loop_messages)
      content  = response["content"] || []

      case response["stop_reason"]
      when "tool_use"
        tool_uses = content.select { |b| b["type"] == "tool_use" }
        loop_messages << { role: "assistant", content: content }
        loop_messages << { role: "user", content: tool_uses.map { |tu|
          { type: "tool_result", tool_use_id: tu["id"], content: dispatch_tool(tu["name"], tu["input"] || {}).to_json }
        } }
        return if @proposal
      when "end_turn"
        return if @proposal
        loop_messages << { role: "assistant", content: content }
        loop_messages << { role: "user", content: [{ type: "text", text: "You have not submitted the proposal. Call propose_quote now with what you have; put anything unresolved in questions." }] }
      else
        raise "Unexpected stop_reason #{response['stop_reason']}"
      end
    end
  end

  def dispatch_tool(name, input)
    if name == "propose_quote"
      @proposal = input.deep_stringify_keys
      { ok: true, note: "Proposal received. Stop." }
    else
      super
    end
  end

  # Quote mode never writes. Anything that would is refused, not rolled back
  # silently — the model should know it asked for something it can't have.
  def run_query(code)
    if WRITE_PATTERNS.any? { |p| code.match?(p) }
      return { blocked: true, reason: "Quote mode is read-only. Parts and quotes are created by the reviewer from your proposal, not by you." }
    end
    super
  end

  # ── Prompt ────────────────────────────────────────────────────────────

  def build_system_prompt
    [core_identity, business_context, customer_rules, pricing_rules, template_rules, quote_mode_rules, schema_section].compact.join("\n\n")
  end

  # The read half of CREATING PARTS: how to find the template whose operation
  # set to copy. The write half is deliberately absent here.
  def template_rules
    part_creation.split("STEP 2 (write)").first
  end

  def quote_mode_rules
    <<~PROMPT
      QUOTE MODE — READ THIS CAREFULLY:
      You are producing a quotation PROPOSAL for a person to review in the HAMS quote
      workbench. You do not create parts, quotes or emails. Your entire output is ONE
      call to propose_quote; prose outside it is discarded.

      Work through it like this:
      1. Read the drawing(s) and enquiry. Identify each distinct part number/issue.
      2. For each part, check Part.matching(customer_id: ..., part_number: ..., part_issue: ...)
         — if it exists, set existing_part_id and reuse its each_price as a sanity check.
      3. Otherwise find the template part (STEP 1 above) and copy its operation
         set into `treatments`, adjusted for this part's spec (thickness, sealing,
         dye, alloy). Record which template you used and what you changed in
         the part's reasoning.
      4. Estimate dimensions and surface area from the drawing (bounding box) and
         price with the rate card. Show the arithmetic in each line's reasoning.
         One line per quantity break requested; if none, quote the MOC and a
         per-unit price as two lines.
      5. JIGGING: the shop wants jigging decided at quote time. If the drawing
         shows an obvious hanging feature (tapped hole, bore, edge that can
         carry a mark) propose jigging_location and jig_type; if not, leave them
         empty and put a question in `questions` describing the options you see.
      6. Anything else you had to assume (alloy, masking, thread protection,
         spec ambiguity) is a question too, with your suggested_answer.

      When the user message contains PREVIOUS PROPOSAL and ANSWERS, this is a
      re-run: keep everything the reviewer didn't question, apply their answers,
      drop the questions they answered, and add new ones only if the answers
      raised them.

      Be concrete and honest in reasoning fields — the reviewer will edit what
      you got wrong, and they can only do that if they can see what you did.
    PROMPT
  end

  def user_content
    blocks = []
    @quote.drawings.each_with_index do |d, i|
      data = fetch_base64(d["cloudinary_url"]) or next
      if d["content_type"].to_s == "application/pdf"
        blocks << { type: "document", source: { type: "base64", media_type: "application/pdf", data: data }, title: d["original_filename"] }
      else
        blocks << { type: "image", source: { type: "base64", media_type: d["content_type"].presence || "image/jpeg", data: data } }
      end
      blocks << { type: "text", text: "(file #{i}: #{d['original_filename']})" }
    end

    customer = @quote.customer
    known = Part.where(customer_id: customer.id).order(updated_at: :desc).limit(25)
                .map { |p| "#{p.part_number}-#{p.part_issue} · #{p.description} · #{p.specification} · each £#{p.each_price}" }

    text = <<~TXT
      CUSTOMER: #{customer.name} (id #{customer.id})
      ENQUIRER: #{[@quote.enquirer_name, @quote.enquirer_email].compact_blank.join(' · ').presence || 'not given'}

      ENQUIRY:
      #{@quote.enquiry.presence || '(no text — work from the drawing)'}

      EXISTING PARTS FOR THIS CUSTOMER (most recent 25):
      #{known.presence&.join("\n") || 'none'}
    TXT

    text += "\n\nPREVIOUS PROPOSAL:\n#{JSON.pretty_generate(@quote.proposal)}" if @quote.proposal.present?
    text += "\n\nANSWERS FROM THE REVIEWER:\n" + @quote.answers.map { |k, v| "- #{k}: #{v}" }.join("\n") if @quote.answers.present?

    blocks << { type: "text", text: text }
    blocks
  end

  def fetch_base64(url, limit = 3)
    return nil if url.blank?
    res = Net::HTTP.get_response(URI(url))
    return fetch_base64(res["location"], limit - 1) if res.is_a?(Net::HTTPRedirection) && limit > 0
    return nil unless res.is_a?(Net::HTTPSuccess)
    Base64.strict_encode64(res.body)
  rescue => e
    Rails.logger.warn "[QuoteProposalJob] could not fetch #{url}: #{e.message}"
    nil
  end
end
