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
  # End-user primes whose work is priced above the rate card. Matched
  # case-insensitively against what the model reports in end_user_prime;
  # applied here, deterministically, to every per-piece line (process AND
  # masking). The MOC stays at the rate-card figure — the shortfall line is
  # recomputed and dropped if the uplifted lines clear it.
  PRIME_UPLIFT = { "Ultra" => 3.1, "Cobham" => 3.1, "Eaton" => 3.1 }.freeze

  PROPOSE_TOOL = {
    name: "propose_quote",
    description: "Submit the finished proposal. Call this exactly once, when the analysis is complete. " \
                 "Everything the workbench shows comes from this call; text outside it is discarded.",
    input_schema: {
      type: "object",
      required: %w[parts lines questions reasoning],
      properties: {
        customer_id:    { type: "string", description: "Organization id of the customer, from Organization.where(is_customer: true) matched by name / email domain / letterhead. Omit if you genuinely cannot match one — never guess an id." },
        customer_name:  { type: "string", description: "The customer's name as HAMS has it (or as the enquiry gives it, if unmatched)." },
        customer_reasoning: { type: "string", description: "One sentence: what you matched the customer from (sender domain, signature, letterhead) — or why you couldn't." },
        end_user_prime: { type: "string", description: "Exactly one of #{PRIME_UPLIFT.keys.join(', ')} when the drawing or enquiry shows the work is ultimately for that prime (title block, logo, their spec references, or stated in the email); otherwise omit. Price at the normal rate card — HAMS applies the prime uplift itself." },
        title:          { type: "string", description: "Short quote title, e.g. 'PD67711-00 — Door Upper Hinge Insert'" },
        summary:        { type: "string", description: "One line: process, spec, thickness. Printed on the quote." },
        enquirer_name:  { type: "string" },
        enquirer_email: { type: "string" },
        notes:          { type: "string", description: "Customer-facing, printed on the quote: exclusions, assumptions, lead time. One or two sentences. NO arithmetic." },
        reasoning:      { type: "string", description: "Two or three sentences: what the drawing is, what process/spec you identified, and any doubt about that reading. No template names, no pricing, no numbers — those belong on the part and the lines." },
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
              material:         { type: "string", description: "The alloy designation as the shop says it: '6082', '7075-T6', '2024-T3', 'LM25'. Never 'Aluminium 6082' or 'Al alloy 7075'." },
              specified_thicknesses: { type: "string", description: "ALWAYS filled: the coating thickness and tolerance the drawing/spec calls for, e.g. '25±5µm', '36–44µm', '~20µm', '50µm min'. Required even when the specification text already mentions it — this field drives inspection." },
              process_type:     { type: "string", description: "anodising | enp | chemical_conversion | ... as Part.process_type uses" },
              aerospace_defense: { type: "boolean" },
              template_part_id: { type: "string", description: "The locked part whose customisation_data you copied the operation set from" },
              treatments:       { type: "array", items: { type: "object" }, description: "operation_selection.treatments exactly as stored on the template, tweaked for this part (type, operation_id, selected_jig_type, selected_alloy, target_thickness, sealing_method, dye_color, masking...)." },
              operation_selection_extra: { type: "object", description: "Other operation_selection keys copied from the template (selected_enp_heat_treatment etc.)" },
              drawing_indexes:  { type: "array", items: { type: "integer" }, description: "Which of the uploaded files are THIS part's drawing(s), by the 'file N' number shown with each file. Required: a part gets only its own drawings attached, never the whole set. Omit only if the part has no drawing among the files." },
              jigging_location: { type: "string", description: "Where/how the part hangs and which surfaces may carry a jig mark. Leave empty if the drawing doesn't say — and ask." },
              jig_type:         { type: "string", description: "One of the shop's jig types, exactly as listed in JIG SELECTION. Always propose one." },
              dimensions_mm:    { type: "object", properties: { l: { type: "number" }, w: { type: "number" }, h: { type: "number" } } },
              surface_area_sqft: { type: "number" },
              reasoning:        { type: "string", description: "Configuration only: which template part you copied (part number, customer) and exactly what you changed. Two sentences. No pricing, no area — that goes on the line." }
            }
          }
        },
        lines: {
          type: "array",
          items: {
            type: "object",
            required: %w[description quantity unit_amount reasoning],
            properties: {
              part_key:    { type: "string", description: "The part this line prices, PER PIECE. ONE line per part (per quantity break): every treatment and any masking summed into unit_amount. Omit (or empty) ONLY for the minimum-order-charge line, which belongs to no part." },
              description: { type: "string", description: "Customer-facing. Each treatment and any masking on its own line, e.g. 'Hard anodise WS T.I. 5031, 50–65 µm, hot water sealed\\nChromate conversion (Alochrom 1200) on designated faces\\nMasking (polyester tape) — chromated electrical faces'. NO part number — the quote shows it in its own column. No prices here." },
              components:  { type: "array", description: "REQUIRED on every part line: the per-piece make-up of unit_amount, one entry per treatment / masking, same order and wording as the description lines. Their unit_amounts MUST sum to the line's unit_amount. Omit on the MOC line.",
                             items: { type: "object", required: %w[description unit_amount],
                                      properties: { description: { type: "string" }, unit_amount: { type: "number" } } } },
              quantity:    { type: "integer", description: "The job quantity for a part line; 1 for the minimum order charge line." },
              unit_amount: { type: "number", description: "GBP ex VAT per piece for a part line. For the MOC line: the SHORTFALL (MOC minus the sum of all part lines), so the job price is the sum of every line." },
              reasoning:   { type: "string", description: "The working for THIS line, readable by a plater in a small box. One block per component, each ending in its per-piece £, then the sum: 'Hard anodise: 181×82×53 → 0.62 sqft × £20 = £12.40\\nAlochrom: 0.62 × £8 = £4.96\\nTape: A 25 cm², loops 2×12.6 → 10 min × £1.00 = £10.00\\nEach £27.36'. Inputs and results only — never the substitution, never the formula re-typed. Then × qty and the MOC comparison. This is the only place numbers are shown." },
            }
          }
        },
        questions: {
          type: "array",
          description: "Decisions you could not settle from the drawing or enquiry and that change the configuration or price. Jigging location and jig type go here when not obvious.",
          items: {
            type: "object",
            required: %w[key question],
            properties: {
              key:              { type: "string" },
              question:         { type: "string", description: "Self-contained, one sentence, answerable in a few words. Say what you'd do either way if it matters." },
              suggested_answer: { type: "string", description: "A short CANDIDATE ANSWER the reviewer can accept as-is (e.g. 'Mask the bore, £1.50/min'), or omit. Never restate the question or describe the drawing here." }
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
    apply_prime_uplift!(@proposal)
    @quote.update!(proposal: @proposal, proposal_error: nil, status: "proposed", proposed_at: Time.current)
  rescue => e
    Rails.logger.error "[QuoteProposalJob] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    Quote.find_by(id: quote_id)&.update_columns(proposal_error: e.message, status: "proposal_failed", updated_at: Time.current)
  end

  private

  def apply_prime_uplift!(prop)
    prime  = PRIME_UPLIFT.keys.find { |k| k.casecmp?(prop["end_user_prime"].to_s.strip) }
    factor = prime && PRIME_UPLIFT[prime]
    prop.delete("prime_uplift")
    return unless factor

    lines    = Array(prop["lines"])
    part_ls  = lines.select { |l| l["part_key"].present? }
    moc_line = lines.find { |l| l["part_key"].blank? }
    base_sum = part_ls.sum { |l| l["quantity"].to_i * l["unit_amount"].to_f }
    moc      = moc_line ? base_sum + moc_line["unit_amount"].to_f : nil

    part_ls.each do |l|
      base = l["unit_amount"].to_f
      l["unit_amount"] = (base * factor).round(2)
      Array(l["components"]).each { |c| c["unit_amount"] = (c["unit_amount"].to_f * factor).round(2) if c.is_a?(Hash) }
      l["reasoning"]   = "#{l['reasoning']}\n#{prime} prime: £#{'%.2f' % base} × #{factor} = £#{'%.2f' % l['unit_amount']} (applied by HAMS)"
    end

    if moc_line
      shortfall = moc - part_ls.sum { |l| l["quantity"].to_i * l["unit_amount"].to_f }
      if shortfall > 0
        moc_line["unit_amount"] = shortfall.round(2)
        moc_line["reasoning"]   = "#{moc_line['reasoning']}\nRecomputed after #{prime} uplift: MOC £#{'%.2f' % moc} − lines → £#{'%.2f' % shortfall}"
      else
        lines.delete(moc_line)
      end
    end

    # A prime end user is NADCAP work whoever the customer is: water break,
    # foil verification and OCV capture on every part on the quote.
    Array(prop["parts"]).each { |p| p["aerospace_defense"] = true if p.is_a?(Hash) }

    prop["end_user_prime"] = prime
    prop["prime_uplift"]   = factor
  end

  # The previous proposal goes back to the model at rate-card prices so it
  # can't compound the uplift on a re-run; the reviewer's edited figures on
  # the build page are uplifted ones, so they get divided down too.
  def base_proposal
    prop   = @quote.proposal.deep_dup
    factor = prop.delete("prime_uplift").to_f
    return prop unless factor > 1
    Array(prop["lines"]).each do |l|
      l["reasoning"] = l["reasoning"].to_s.sub(/\n[^\n]*\(applied by HAMS\)\z/, "").sub(/\nRecomputed after .*\z/m, "")
      next if l["part_key"].blank?
      l["unit_amount"] = (l["unit_amount"].to_f / factor).round(2)
      Array(l["components"]).each { |c| c["unit_amount"] = (c["unit_amount"].to_f / factor).round(2) if c.is_a?(Hash) }
    end
    prop
  end

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
      when "max_tokens"
        raise "The proposal was too large for one response (#{max_tokens} tokens) — " \
              "fewer parts per quote, or raise QuoteProposalJob#max_tokens"
      else
        raise "Unexpected stop_reason #{response['stop_reason']}"
      end
    end
  end

  # One propose_quote call carrying several fully-configured parts (each with
  # its copied treatments array) runs well past the 4k chat default.
  def max_tokens   = 16_000
  def read_timeout = 600

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
  # Drawing URLs and file bytes must not be reachable through the query tool
  # on an ITAR quote: the Cloudinary URLs are public-by-URL, so a query that
  # returns one (or opens it) would hand the model what the flag withholds.
  ITAR_PATTERNS = [/Net::HTTP/, /URI\.open/, /open-uri/, /open\(/, /Base64/, /cloudinary/i, /\.files\b/,
                   /\.drawings\b/, /file_preview_url|file_thumbnail_url|generate_file_download_url/].freeze

  def run_query(code)
    if WRITE_PATTERNS.any? { |p| code.match?(p) }
      return { blocked: true, reason: "Quote mode is read-only. Parts and quotes are created by the reviewer from your proposal, not by you." }
    end
    if @quote.itar? && ITAR_PATTERNS.any? { |p| code.match?(p) }
      return { blocked: true, reason: "This is an ITAR quote: drawings, file lists and URLs are not available to you. Work from the description." }
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
      1. Read the drawing(s) and enquiry. (On an ITAR quote the user message
         says so and gives a DRAWING DESCRIPTION in place of the files — treat
         that description as the drawing throughout, and assign drawing_indexes
         from the file list it gives you.) Identify each distinct part number/issue,
         and for each part record WHICH files are its drawings (drawing_indexes,
         by the "file N" label). Three drawings for three parts means each part
         gets one — match by the part number in the title block or filename.
      1b. CUSTOMER and END USER are two different things. The customer is who is
         asking (see CUSTOMER in the message). The end user is who the part is
         ultimately for: if the title block, logo, spec references (e.g. DS
         26.00 = Cobham) or the email shows it is for one of the primes in
         end_user_prime's list, set end_user_prime to that name. Price at the
         NORMAL rate card regardless — do not multiply anything yourself; HAMS
         applies the prime rate after you and shows the reviewer both figures.
         Say in the overall reasoning what you spotted the prime from.
      2. For each part, check Part.matching(customer_id: ..., part_number: ..., part_issue: ...)
         — if it exists, set existing_part_id and reuse its each_price as a sanity check:
         if your rate-card price differs from the saved each_price by more than
         25% either way, STOP speculating about why and raise a question —
         "Saved each price £X vs rate card £Y — which?" with the saved price as
         the suggested_answer. Do not write a paragraph guessing at uplifts or
         discrepancies in the working; one line "saved £X — see question" is
         all. The reviewer knows the history; you don't. (The saved price
         already includes any prime uplift, so compare it with your figure
         × the uplift when end_user_prime is set.)
      3. Otherwise find the template part (STEP 1 above) and copy its operation
         set into `treatments`, adjusted for this part's spec (thickness, sealing,
         dye, alloy). Record which template you used and what you changed in
         the part's reasoning.
      4. Estimate dimensions and surface area from the drawing (bounding box) and
         price with the rate card. Show the arithmetic in each line's reasoning.
         PRICE LINES ARE PER PIECE — the part's each price, which is SAVED ON
         THE PART as what the customer was quoted per part. ONE LINE PER
         PART: price every treatment in the part's treatments array and any
         masking SEPARATELY in the working, then SUM them into that part's
         single unit_amount. Chromic anodise + chromate + masking on one part
         is ONE line with three components in its reasoning and all three
         named in its description, not three lines. The reviewer and the
         customer both see one price per part; the breakdown lives in the
         working only. Quantity = the job quantity, unit_amount = the summed
         price per piece.
         NEVER a "qty 1" lot line for a part, and NEVER the MOC as a part's
         price: if the sum of the part lines for the job is under the minimum
         order charge (£250; £125 when the job is chemical conversion only),
         add ONE extra line with NO part_key, description "Minimum order
         charge", quantity 1, unit_amount = the shortfall. The job price is
         then the sum of all lines, and the part's each price stays true.
         Example, 5 off: anodise £6.40 + masking £22.50 = £28.90 each →
         lines: part 5 × £28.90 (working shows both components), MOC 1 ×
         £105.50; job price £250.00; part each price £28.90.
         One set of lines per quantity break requested; if no quantity is
         given, quote for 1 off (the MOC line will carry most of it) and say
         in the summary where the per-piece price takes over.
      4b. MASKING: apply the masking rule from the rate card. Tapped and
         small holes at ≥30µm are BUNGED and included in the price — set
         "bungs" in masking_methods, no line, no question, unless the line is
         high-volume and low-value (rate card says when). Faces the drawing
         marks for masking, bores, grooves and splines are rubber lacquer:
         price it by minutes as a component of the part's line (named in the
         description, worked in the reasoning) and set
         "45_stopping_off_lacquer" with the features. Never put lacquered
         features under "bungs" or holes under lacquer. The question, if any,
         is about WHICH features — never whether to quote it.
      4c. THICKNESS: apply the build-up rule from the rate card before choosing
         the operation. Say in the part reasoning whether the drawing gave
         film thickness or surface build-up and what film you targeted.
      5. JIGGING: the shop wants jigging decided at quote time. Apply JIG
         SELECTION from the rate card: ALWAYS fill jig_type with one of the
         listed jigs and jigging_location with the feature it uses. A tapped
         hole the drawing excludes from the coating is the answer whenever
         one exists — no question needed. If you had
         to guess, also raise a question naming the alternative you rejected —
         but the fields are still filled with your best answer.
      5b. Apply CROSS-CHECK THE PAPERWORK: revision, part number, quantity,
         spec — mismatches become questions with a recommended resolution.
      6. Anything else you had to assume that changes the configuration or the
         price (alloy, masking, thread protection, spec ambiguity) is a question
         too, with a short suggested_answer the reviewer can accept as-is.

      NEVER ASK WHAT YOU HAVE BEEN TOLD. Before writing a question, check the
      enquiry text and any reviewer answers: if they state the masking scope,
      the price to allow for it, the jig, the quantity, the revision to use,
      or anything else — that is the answer. Use it as given, say "per the
      enquiry" in the working, and do not raise a question about it. A
      question the enquiry already answers wastes the reviewer's time and
      makes you look like you didn't read it.

      DO NOT ASK ABOUT:
      - The company in the drawing's title block vs the customer. The prime/OEM
        on the drawing (Williams, Airbus, Leonardo...) is routinely NOT the
        customer — the customer is a subcontractor. That is normal and needs no
        question. aerospace_defense is true when the CUSTOMER is aerospace/defence
        OR the part is for a prime (end_user_prime set) — a subcontractor's
        Ultra part is aero work even though the subcontractor isn't.
      - Lead time, QA paperwork, or anything that doesn't change the config or price.

      ENQUIRER: fill enquirer_name/email ONLY from the enquiry text. Never use the
      HAMS user. Leave blank if the enquiry doesn't give them.

      CUSTOMER-FACING FIELDS: title, summary, notes and every line's
      description are printed on the quote PDF and emailed to the customer.
      They carry WHAT is quoted — process, spec, thickness, the features a
      masking line covers — and never HOW we arrived at it: no minutes, no
      rates, no sqft, no MOC comparison, no template part numbers, no
      "assumed" or "estimated". All of that goes in the reasoning fields,
      which only the reviewer sees.

      SAY EACH THING ONCE. The reviewer sees overall reasoning, the part card and
      the price lines side by side. Overall = what the drawing is and the process
      read. Part = template and changes. Line = the arithmetic. Do not repeat the
      surface-area calculation or the MOC comparison outside the line's working.

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
    # drawings_for_assistant is [] for an ITAR quote. Never read
    # @quote.drawings here — that list is for Cloudinary, the workbench and
    # the email, not the model.
    @quote.drawings_for_assistant.each_with_index do |d, i|
      data = fetch_base64(d["cloudinary_url"]) or next
      if d["content_type"].to_s == "application/pdf"
        blocks << { type: "document", source: { type: "base64", media_type: "application/pdf", data: data }, title: d["original_filename"] }
      else
        blocks << { type: "image", source: { type: "base64", media_type: d["content_type"].presence || "image/jpeg", data: data } }
      end
      blocks << { type: "text", text: "(file #{i}: #{d['original_filename']})" }
    end

    customer = @quote.customer
    if customer
      known = Part.where(customer_id: customer.id).order(updated_at: :desc).limit(25)
                  .map { |p| "#{p.part_number}-#{p.part_issue} · #{p.description} · #{p.specification} · each £#{p.each_price}" }
      customer_block = <<~TXT
        CUSTOMER: #{customer.name} (id #{customer.id}) — confirmed by the reviewer; return it as customer_id/customer_name.

        EXISTING PARTS FOR THIS CUSTOMER (most recent 25):
        #{known.presence&.join("\n") || 'none'}
      TXT
    else
      customer_block = <<~TXT
        CUSTOMER: NOT SET. Identify the customer from the enquiry — sender email
        domain, signature block, letterhead, PO/RFQ header — and match it to HAMS:
          Organization.where(is_customer: true).where("name ILIKE ?", "%acme%").pluck(:id, :name)
        Try the company name, then the email domain's distinctive word. Return
        customer_id and customer_name; if nothing matches, give customer_name as
        the enquiry has it, leave customer_id out, and say so in customer_reasoning.
        The prime/OEM on the drawing is usually NOT the customer — the customer is
        whoever is asking. Once matched, list their recent parts yourself
        (Part.where(customer_id: ...).order(updated_at: :desc).limit(25)) before
        checking Part.matching.
      TXT
    end

    if @quote.itar?
      files = @quote.drawings.each_with_index.map { |d, i| "  file #{i}: #{d['original_filename']}" }.join("\n")
      itar_block = <<~TXT
        ITAR / EXPORT-CONTROLLED QUOTE — THE DRAWINGS ARE NOT PROVIDED TO YOU.
        #{@quote.drawings.length} file(s) are held on the quote and will be attached to the
        part(s) by HAMS; you only see their names, for drawing_indexes:
        #{files.presence || '  (none)'}
        Work from the enquiry and the reviewer's description below. Do not ask
        for the drawing, do not try to fetch it, and do not guess what it shows
        beyond the description: dimensions_mm and surface_area_sqft come from
        the description if it gives them, otherwise price from the nearest
        existing part for this customer and raise a question for the size.

        DRAWING DESCRIPTION (written by the reviewer):
        #{@quote.drawing_description}

      TXT
    end

    text = <<~TXT
      #{itar_block}#{customer_block}
      ENQUIRER: #{[@quote.enquirer_name, @quote.enquirer_email].compact_blank.join(' · ').presence || 'not given — take it from the enquiry'}

      ENQUIRY:
      #{@quote.enquiry.presence || '(no text — work from the drawing)'}
    TXT

    text += "\n\nPREVIOUS PROPOSAL (prices shown at the rate card — HAMS applies any prime uplift after you):\n#{JSON.pretty_generate(base_proposal)}" if @quote.proposal.present?
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
