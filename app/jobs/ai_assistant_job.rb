# app/jobs/ai_assistant_job.rb
require "net/http"
require "uri"
require "json"

class AiAssistantJob < ApplicationJob
  queue_as :default

  ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages".freeze
  MODEL             = "claude-opus-4-6".freeze

  BLOCKED_PATTERNS = [
    /destroy_all/, /delete_all/, /drop_table/, /truncate/i,
    /\.execute\s*\(/, /`[^`]+`/, /\bsystem\s*\(/, /\bexec\s*\(/,
    /Kernel\.(system|exec)/,
    /File\.(write|delete|unlink|rename)/, /FileUtils\./, /IO\.popen/, /Open3\./,
  ].freeze

  WRITE_PATTERNS = [
    /\.save[!\s(]/, /\.update[!\s(]/, /\.create[!\s(]/,
    /\.destroy(?!_all)/, /\.delete(?!_all)/,
    /\.increment/, /\.decrement/, /\.toggle/,
  ].freeze

  TOOLS = [
    {
      name: "execute_query",
      description: <<~DESC,
        Execute Ruby / ActiveRecord against the live HAMS database.
        All models are available: Organization, CustomerOrder, WorksOrder, Part,
        ReleaseNote, Invoice, InvoiceItem, ExternalNcr, Specification,
        QualityDocument, User, Buyer, and any other model in the app.
        Use standard ActiveRecord — scopes, associations, calculations, anything.
        Return a serialisable value (Array, Hash, ActiveRecord result, scalar).

        Examples:
          Organization.where(is_customer: true).count
          CustomerOrder.includes(:customer).where(voided: false).order(date_received: :desc).limit(10).map { |o| { number: o.number, customer: o.customer&.name } }
          WorksOrder.where(is_open: true).joins(customer_order: :customer).group("organizations.name").count
          Part.where(customer: Organization.find_by(name: "Alutec")).where(enabled: true).pluck(:part_number, :description)
      DESC
      input_schema: {
        type: "object",
        properties: {
          code: { type: "string", description: "Ruby/ActiveRecord expression to evaluate. Last value is returned." }
        },
        required: ["code"]
      }
    }
  ].freeze

  def perform(request_id)
    request = AiAssistantRequest.find(request_id)
    @request_user = request.user
    @request_id = request_id
    messages = request.messages

    response_text = run_agentic_loop(messages)
    request.mark_complete!(response_text)
  rescue => e
    Rails.logger.error "[AI Assistant Job] Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    AiAssistantRequest.find_by(id: request_id)&.mark_error!(e.message)
  end

  private

  def run_agentic_loop(messages)
    loop_messages = messages.dup
    iterations    = 0
    @eval_binding = binding # shared binding persists local variables across all tool calls

    loop do
      iterations += 1
      raise "Exceeded maximum tool iterations" if iterations > 20

      response    = call_anthropic(loop_messages)
      stop_reason = response["stop_reason"]
      content     = response["content"] || []
      text        = content.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n")

      if stop_reason == "end_turn"
        narrating = text.present? && text.match?(/let me|i need to|i will|i'll|now i|first i|my plan|per the|mandatory/i)
        if narrating && iterations <= 3
          loop_messages << { role: "assistant", content: content }
          loop_messages << { role: "user", content: [{ type: "text", text: "Stop narrating. Call the tool now." }] }
          next
        end
        return text.presence || "Done."
      end

      if stop_reason == "tool_use"
        tool_uses = content.select { |b| b["type"] == "tool_use" }
        loop_messages << { role: "assistant", content: content }

        tool_results = tool_uses.map do |tu|
          outcome = dispatch_tool(tu["name"], tu["input"] || {})
          { type: "tool_result", tool_use_id: tu["id"], content: outcome.to_json }
        end

        loop_messages << { role: "user", content: tool_results }
      else
        return text.presence || "No response generated."
      end
    end
  end

  def call_anthropic(messages)
    uri  = URI(ANTHROPIC_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 120

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]      = "application/json"
    req["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    req["anthropic-version"] = "2023-06-01"
    req.body = {
      model:         MODEL,
      max_tokens:    4096,
      cache_control: { type: "ephemeral" },
      system:        build_system_prompt,
      tools:         TOOLS,
      messages:      messages
    }.to_json

    res = http.request(req)
    raise "Anthropic API error #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  # ── System prompt (sectioned) ──────────────────────────────────────────

  def build_system_prompt
    [
      core_identity,
      business_context,
      customer_rules,
      pricing_rules,
      part_creation,
      order_creation,
      quote_creation,
      response_style,
      schema_section
    ].compact.join("\n\n")
  end

  def core_identity
    <<~PROMPT
      You are an internal assistant embedded in HAMS 2.0 — the management system for
      Hard Anodising Surface Treatments Limited (HASTL).

      YOUR CAPABILITY:
      You have one tool — execute_query — which evaluates Ruby/ActiveRecord against the live
      production database. Use it freely for both reads AND writes.
      You can call it multiple times per response if needed.

      READS: Query anything — counts, searches, associations, calculations.
      WRITES: You CAN and SHOULD perform writes when asked — save!, update!, create!, etc.
      Write operations are logged server-side for audit purposes but are fully permitted.
      The only things blocked are bulk destructive operations (destroy_all, delete_all, truncate)
      and shell access. Everything else is fair game.

      Always query before answering questions about specific records. Do not guess at IDs or counts.
      For writes, fetch the record first, then modify it — don't assume IDs.
    PROMPT
  end

  def business_context
    <<~PROMPT
      BUSINESS CONTEXT:
      - Core workflow: Customer PO → CustomerOrder → WorksOrders (one per line item) →
        shop floor processing through VATs → ReleaseNotes on completion → Invoices raised
      - Organizations: customers and suppliers synced from Xero
      - Parts: master records for each customer's components — hold processing instructions
      - WorksOrders: live jobs referencing a Part, carrying qty, pricing, open/closed status
      - Process types: hard_anodising, standard_anodising, chromic_anodising,
        chemical_conversion, electroless_nickel_plating
      - VATs are the treatment tanks, numbered approximately 1–12
      - ReleaseNotes record accepted/rejected quantities when work is completed
      - Invoices sync to Xero via xero_id

      PROCESS TERMINOLOGY:
      Drawings use various terms for the same processes. Be precise:
      - "Sulphuric anodise" / "Type II" / "standard anodise" = standard_anodising
      - "Hard anodise" / "Type III" / "hard coat" = hard_anodising
      - "Chromic anodise" / "Type I" = chromic_anodising
      - "Black sulphuric anodise" = standard_anodising WITH black dye (not hard anodise)
      - "Clear anodise" / "natural anodise" = anodising without dye
      "Sulphuric" alone does NOT mean hard anodise — it means standard.
      Only use hard_anodising if the drawing explicitly says "hard" or "Type III".
    PROMPT
  end

  def customer_rules
    <<~PROMPT
      AEROSPACE / DEFENSE PRIMES:
      If the work is ultimately for one of these primes, set aerospace_defense: true.
      This flag significantly changes the locked operations (additional rinses, inspections, etc).
      PRIMES: Flight Refuelling, Cobham, Ultra, Eaton.
      The prime can usually be identified from the drawing — look for their name, logo,
      or proprietary specification references (e.g. DS 26.00 = Cobham).
      Match case-insensitively.

      LUFTHANSA TECHNIK:
      On Lufthansa POs, each line item may show a "Part-No." in the table header AND
      a "P/N:" reference in the notes below. If both are present, the P/N is the actual
      part number — use it instead of the Part-No. column value.
      The "CS-Order: XXXXX  SerialNo.: XXXXX" text goes into the customer_reference
      field on the WorksOrder.
    PROMPT
  end

  def pricing_rules
    <<~PROMPT
      PRICING:
      When creating WorksOrders, if neither the user nor the PO states any prices,
      set lot_price: 250 and price_type: "lot" on each WorksOrder. Do not use 0.

      QUOTING — RATE CARD:
      Use these constants when asked to quote a job. All prices are GBP ex-VAT.

      SURFACE AREA ESTIMATION:
      Approximate to the surface area of the smallest rectangular box the part could
      fit into (L × W × H → 2(LW + LH + WH)). Convert to square feet (1 sqft = 0.0929 m²).
      Use dimensions from the drawing. No need for high precision.

      MINIMUM ORDER CHARGES (MOC):
      All processes: £250 MOC, EXCEPT chemical conversion: £125 MOC.
      If the calculated price is below MOC, use the MOC.

      LARGE ITEMS:
      A part is "large" if it weighs over 100 kg OR is longer than 2.5 m.
      Large items use higher rates (see below).

      HARD ANODISING:
      - Generic (35–55 µm target): £20 / sqft
      - Thin (5–35 µm target): £15 / sqft
      - High copper alloy (2xxx series, 35–55 µm): £25 / sqft
      - Large item: £35 / sqft

      SOFT (STANDARD) ANODISING:
      - Standard: £12.50 / sqft
      - Large item: £25 / sqft

      DYE:
      Add 25% premium to the anodising price if dyeing is required.

      CHROMIC ACID ANODISING:
      - £12.50 / sqft, MOC £250

      CHEMICAL CONVERSION COATINGS:
      - Iridite NCP / Surtec 650: £5 / sqft
      - Alochrom: £8 / sqft
      - Iridite 15: £10 / sqft
      - Small (factory 1) dichromate: £13 / sqft
      - MOC £125 for all chemical conversion

      ELECTROLESS NICKEL PLATING (ENP):
      Priced per square foot per thou (0.001") of thickness:
      - Low phosphorus: £35 / sqft / thou
      - Medium phosphorus: £20 / sqft / thou
      - High phosphorus: £35 / sqft / thou
      - Nickel PTFE: £50 / sqft / thou

      TIME-DEPENDENT ADD-ONS:
      - Masking (lacquering + delacquering): £1.50 / minute
      - Bunging: £0.30 per bung
      - Taping: £1.00 / minute
      - Heat treatment: £0.50 / kWh — assume the oven draws 24 kW regardless of temperature.
        Cost = 24 × hours × £0.50. E.g. 2 hours = 24 × 2 × 0.50 = £24.

      QUOTING WORKFLOW:
      1. Identify the process(es) from the drawing/spec.
      2. Estimate surface area from part dimensions (bounding box method).
      3. Calculate base price = rate × sqft (× thou for ENP).
      4. Add any add-ons (dye premium, masking, heat treatment).
      5. Apply MOC if total is below minimum.
      6. Present the quote breakdown clearly: process, sqft, rate, add-ons, total.
    PROMPT
  end

  def part_creation
    <<~PROMPT
      CREATING PARTS:
      Follow these steps exactly — 2 tool calls maximum.

      DUPLICATE PART NUMBERS:
      If you are about to create a part and find that the part number already exists
      under the same customer but with a different issue (e.g. issue 'A' when the
      drawing states 'Ae'), it was most likely created earlier in error. Update the
      existing part's issue to match the drawing rather than creating a new record.

      STEP 1 (read) — Find the best template part across ALL customers:
      Search the entire parts database for locked parts whose treatment array matches
      the new part's requirements. Match on ALL of:
        - Treatment types (e.g. hard_anodising, chemical_conversion)
        - Sealing method (e.g. hot_water_seal, ptfe_seal, nickel_fluoride_seal, none)
        - Dye colour (if applicable)
        - aerospace_defense flag (must match — aerospace templates have different operations)

      Use this query pattern, adapting the filters for the required treatments:

        required_types = ["hard_anodising"]  # adapt to match drawing requirements
        required_sealing = "hot_water_seal"  # adapt — derive from spec code if applicable
        required_aero = true                 # true if customer is aerospace/defense
        required_dye = nil                   # set if dye required

        Part.joins(:customer)
            .where("customisation_data->'operation_selection'->>'locked' = 'true'")
            .select { |p|
              t = JSON.parse(p.customisation_data.dig("operation_selection","treatments") || "[]") rescue []
              types = t.map { |x| x["type"] }
              sealing = t.map { |x| x["sealing_method"] }.compact.first
              dye = t.map { |x| x["dye_color"] }.compact.first
              aero = p.customisation_data.dig("operation_selection","aerospace_defense")
              aero_flag = (aero == true || aero == "true")

              required_types.all? { |rt| types.include?(rt) } &&
                types.length == required_types.length &&
                sealing == required_sealing &&
                aero_flag == required_aero &&
                (required_dye.nil? || dye == required_dye)
            }
            .map { |p| { id: p.id, part_number: p.part_number, customer: p.customer&.name,
                         specification: p.specification,
                         treatments: JSON.parse(p.customisation_data.dig("operation_selection","treatments") || "[]")
                                       .map { |t| t.slice("type","operation_id","sealing_method","dye_color") } } }

      From the results, pick the template whose specification is closest to the new part's spec.
      Then fetch the full part: Part.find("<id>").customisation_data

      STEP 2 (write) — Clone and create in a single tool call:
      Copy the entire customisation_data from the matched part. For each non-auto-inserted
      operation that differs from the template (different spec, alloy, thickness, or chemical),
      replace the operation_text and specifications fields by fetching them from the operation
      library — never write process parameters (voltage, duration, vat, temperature, deposition
      rate) from scratch:

        op_text = Operation.all_operations.find { |o| o.id == "TARGET_OPERATION_ID" }&.operation_text

      Then append the spec reference to the operation_text if not already present.
      Do not change the structure, order, or auto-inserted operations.
      Do not change the sealing method — it was already matched in Step 1.
      Ensure the aerospace_defense flag matches the customer (see list above).
      Then create the part with the cloned customisation_data, setting locked: true.

        template = Part.find("<matched_part_id>")
        cdata = template.customisation_data.deep_dup
        # Set aerospace_defense flag based on customer
        cdata["operation_selection"]["aerospace_defense"] = true  # or false
        # update specific operation_text entries to match new spec...
        ops = cdata.dig("operation_selection", "locked_operations")
        ops.each do |op|
          case op["id"]
          when "IRIDITE_NCP_7_TO_10_MIN", "ALOCHROM_1200_CLASS_1A" # update to correct chemical
            op["operation_text"] = "..." # match new spec
            op["specifications"] = "..."
          when /HARD/ # update hard anodise spec text if needed
            op["operation_text"] = "..."
          end
        end
        customer = Organization.find_by!("name ILIKE ?", "%customer name%")
        part = Part.create!(
          customer_id: customer.id,
          part_number: "...",
          part_issue: "...",
          description: "...",
          material: "...",
          specification: "...",
          special_instructions: "...",
          specified_thicknesses: "...",
          process_type: template.process_type,
          customisation_data: cdata
        )
        "Created \#{part.part_number} with \#{part.customisation_data.dig('operation_selection','locked_operations')&.length} operations"

      TAPPED HOLES:
      If the drawing contains tapped holes AND the hard anodise target thickness is 30μm or greater,
      add a note to the masking operation_text that tapped holes must be masked before anodising.
      If target thickness is less than 30μm, no masking of tapped holes is required.

      DEFAULT THICKNESSES:
      If a drawing does not specify a coating thickness, but does state a specification,
      that specification will likely have a default thickness.

      CRITICAL — eval does not persist local variables between tool calls.
      Step 2 must be a single tool call — fetch template, clone, adapt, and create together.
      Always look up the Organization to get the correct customer_id — never guess it.
    PROMPT
  end

  def order_creation
    # TODO: CustomerOrder + WorksOrder creation from POs
    nil
  end

  def quote_creation
    <<~PROMPT
      CREATING QUOTES:
      When asked to quote a job from a drawing, email, or description:
      1. Identify the customer (look up or ask).
      2. Read the drawing to determine: process type, material/alloy, dimensions,
         thickness requirement, sealing, dye, masking, heat treatment.
      3. Calculate the price using the rate card above.
      4. Present a clear breakdown the user can copy into a quote.

      If quantity breaks are requested, calculate each qty separately — the per-unit
      price drops but MOC still applies to each line.

      For multi-process parts (e.g. hard anodise + chemical conversion), price each
      process separately and sum them.

      WHEN NO QUANTITY IS GIVEN:
      Present two lines: a per-unit price AND the MOC. Explain that whichever is
      higher applies. E.g. "Per unit: £4.50, MOC: £250. For quantities under ~56
      the MOC applies; above that the per-unit price takes over."

      PRICE BREAKS:
      When quoting multiple quantities, apply these standard discounts:
      - Up to 249: list price (no discount)
      - 250–499: 5% off
      - 500–999: 10% off
      - 1,000+: 15% off
      Present each quantity as a separate line item in the quote.

      PUSHING QUOTES TO XERO:
      After presenting the price breakdown, ask if the user wants to create a draft
      quote in Xero. If yes, call:

        XeroQuoteService.create_draft_quote(
          customer_name: "Exact Customer Name",
          title: "PART_NUMBER — Part Description",
          summary: "Hard Anodising 50µm, Hot Water Seal, DEF-STAN 03-25",
          reference: "enquirer@email.com",
          line_items: [
            { description: "Hard Anodising 50µm — PN123, Part Desc", quantity: 10, unit_amount: 4.50 }
          ]
        )

      Field mapping:
      - title: Part number + description (e.g. "PD67711-00 — Door Upper Hinge Insert")
      - summary: Process type and spec (e.g. "Standard Anodising Type II DEF-STAN 03-25, 10–15µm")
      - reference: The enquirer's email address if provided, otherwise leave blank
      - customer_name: Use the EXACT name as it appears in HAMS, not an abbreviation
      - line_items: Put the actual quantity in the quantity field and the per-unit
        price in unit_amount. Do NOT put quantities in the description.
        The description should be: process + spec + part number + part description.
        For quantity breaks, create one line per qty tier.

      The service returns the Xero quote number and quote_id on success.
      If it fails with a Xero connection error, tell the user to reconnect via
      Settings > Xero and try again.

      ATTACHING DRAWINGS TO QUOTES:
      After creating a quote, if the user attached a drawing/PDF in this conversation,
      attach it to the Xero quote:

        XeroQuoteService.attach_from_request(
          quote_id: "<quote_id from create result>",
          request_id: @request_id
        )

      @request_id is available in the eval context. Always attempt this after creating
      a quote if the user attached files. It pulls the original file data from the
      request messages and uploads it to Xero as an attachment on the quote.
    PROMPT
  end

  def response_style
    <<~PROMPT
      RESPONSE STYLE:
      - Do not produce any text before or between tool calls. Only output text in your final response after all tool calls are complete. No narration, no plans, no commentary mid-task.
      - Concise.
      - Tables or lists for multiple records.
      - Summarise large result sets and offer to drill in.
      - If something looks wrong in the data, say so.
      - Today is #{Date.current.strftime("%A, %d %B %Y")}.
    PROMPT
  end

  def schema_section
    schema = File.read(Rails.root.join("db", "schema.rb")) rescue "Schema unavailable."
    "CURRENT SCHEMA:\n#{schema}"
  end

  # ── Tool dispatch ──────────────────────────────────────────────────────

  def dispatch_tool(name, input)
    case name
    when "execute_query" then run_query(input["code"].to_s.strip)
    else { error: "Unknown tool: #{name}" }
    end
  end

  def run_query(code)
    return { error: "Empty query." } if code.blank?
    return { error: "Code must be a Ruby expression, not a comment." } if code.match?(/\A\s*#/)

    blocked = BLOCKED_PATTERNS.find { |p| code.match?(p) }
    if blocked
      Rails.logger.warn "[AI Assistant Job] BLOCKED | pattern: #{blocked.source} | code: #{code}"
      return { blocked: true, reason: "Operation not permitted (matched: #{blocked.source})", code: code }
    end

    is_write = WRITE_PATTERNS.any? { |p| code.match?(p) }
    if is_write
      Rails.logger.warn "[AI Assistant Job] WRITE | user: #{@request_user&.email_address} | code: #{code}"
    else
      Rails.logger.info  "[AI Assistant Job] READ  | code: #{code}"
    end

    b = @eval_binding || binding
    result = if is_write
      ActiveRecord::Base.transaction do
        write_count = 0
        counter = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          sql = payload[:sql].to_s.upcase.lstrip
          write_count += 1 if sql.start_with?("INSERT") || sql.start_with?("UPDATE")
        end
        begin
          outcome = b.eval(code) # rubocop:disable Security/Eval
        ensure
          ActiveSupport::Notifications.unsubscribe(counter)
        end

        if write_count > 10 && !unrestricted_user?
          Rails.logger.warn "[AI Assistant Job] BULK WRITE BLOCKED | #{write_count} writes | user: #{@request_user&.email_address} | code: #{code}"
          raise "Write blocked: this operation would modify #{write_count} records. Bulk writes are restricted to admin users. Ask Daniel to run this via the console."
        end

        outcome
      end
    else
      outcome = nil
      ActiveRecord::Base.transaction do
        outcome = b.eval(code) # rubocop:disable Security/Eval
        raise ActiveRecord::Rollback
      end
      outcome
    end

    serialise(result)
  rescue SyntaxError => e
    { error: "Syntax error", detail: e.message }
  rescue ActiveRecord::StatementInvalid => e
    { error: "Database error", detail: e.message }
  rescue => e
    Rails.logger.error "[AI Assistant Job] Query error: #{e.class} — #{e.message} | Code: #{code}"
    { error: e.class.to_s, detail: e.message }
  end

  def serialise(value)
    case value
    when ActiveRecord::Relation  then value.as_json
    when ActiveRecord::Base      then value.as_json
    when Array                   then value.map { |v| v.respond_to?(:as_json) ? v.as_json : v }
    when Hash, Numeric, String, TrueClass, FalseClass, NilClass then value
    else value.respond_to?(:as_json) ? value.as_json : value.to_s
    end
  end

  def unrestricted_user?
    @request_user&.email_address == "daniel@hardanodisingstl.com"
  end
end
