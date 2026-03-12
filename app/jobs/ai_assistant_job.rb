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
        # Claude narrated instead of acting — push it back once, then give up
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
    http.read_timeout = 120  # Jobs aren't subject to Heroku's 30s HTTP timeout

    req = Net::HTTP::Post.new(uri)
    req["Content-Type"]      = "application/json"
    req["x-api-key"]         = ENV["ANTHROPIC_API_KEY"]
    req["anthropic-version"] = "2023-06-01"
    req.body = {
      model:      MODEL,
      max_tokens: 4096,
      system:     build_system_prompt,
      tools:      TOOLS,
      messages:   messages
    }.to_json

    res = http.request(req)
    raise "Anthropic API error #{res.code}: #{res.body}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  def build_system_prompt
    schema = File.read(Rails.root.join("db", "schema.rb")) rescue "Schema unavailable."

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

    AEROSPACE / DEFENSE PRIMES:
      If the work is ultimately for one of these primes, set aerospace_defense: true.
      This flag significantly changes the locked operations (additional rinses, inspections, etc).
      PRIMES: Flight Refuelling, Cobham, Ultra, Eaton, Lufthansa.
      The prime can usually be identified from the drawing — look for their name, logo,
      or proprietary specification references (e.g. DS 26.00 = Cobham).
      Match case-insensitively.

      Lufthansa Technik Landing Gear Services UK:
      On Lufthansa POs, each line item may show a "Part-No." in the table header AND
      a "P/N:" reference in the notes below. If both are present, the P/N is the actual
      part number — use it instead of the Part-No. column value.
      The "CS-Order: XXXXX  SerialNo.: XXXXX" text goes into the customer_reference
      field on the WorksOrder.

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

      DUPLICATE PART NUMBERS:
      If you are about to create a part and find that the part number already exists
      under the same customer but with a different issue (e.g. issue 'A' when the
      drawing states 'Ae'), it was most likely created earlier in error. Update the
      existing part's issue to match the drawing rather than creating a new record.

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

      RESPONSE STYLE:
      - Do not produce any text before or between tool calls. Only output text in your final response after all tool calls are complete. No narration, no plans, no commentary mid-task.
      - Concise.
      - Tables or lists for multiple records.
      - Summarise large result sets and offer to drill in.
      - If something looks wrong in the data, say so.
      - Today is #{Date.current.strftime("%A, %d %B %Y")}.

      CURRENT SCHEMA:
      #{schema}
    PROMPT
  end

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
      Rails.logger.warn "[AI Assistant Job] WRITE | code: #{code}"
    else
      Rails.logger.info  "[AI Assistant Job] READ  | code: #{code}"
    end

    b = @eval_binding || binding
    result = if is_write
      ActiveRecord::Base.transaction { b.eval(code) } # rubocop:disable Security/Eval
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
end
