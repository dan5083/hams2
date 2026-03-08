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

      CREATING PARTS:
      Follow these steps exactly:

      STEP 1 — Find a similar part to use as a template.
      Query parts that have the same or equivalent treatment combination as the new part.
      The treatments array is the key — match on process types and dye colour:

        Part.joins(:customer)
            .where("customisation_data->'operation_selection'->>'locked' = 'true'")
            .select { |p|
              t = JSON.parse(p.customisation_data.dig("operation_selection","treatments") || "[]") rescue []
              types = t.map { |x| x["type"] }
              types.include?("hard_anodising") && types.include?("chemical_conversion") # adapt to match
            }
            .map { |p| { id: p.id, part_number: p.part_number, customer: p.customer&.name,
                         treatments: JSON.parse(p.customisation_data.dig("operation_selection","treatments") || "[]")
                                        .map { |t| t.slice("type","operation_id","sealing_method","dye_color","selected_jig_type") } } }

      Pick the closest match — same process types, same dye colour if applicable.

      STEP 2 — Adapt the treatments array.
      Copy the treatments array from the matched part. Then adjust only what differs:
      - operation_id: swap to match the correct spec/alloy/thickness for the new part
          (check the matched part's operation_id as a guide to naming conventions)
      - sealing_method: adjust if the spec requires something different
      - dye_color: adjust if different
      - masking_methods: set if the new part has selective treatment areas
      Leave everything else (jig type, stripping fields etc.) as copied from the template.

      STEP 3 — Create the part and call auto_lock_for_editing! in a SINGLE tool call:

        template = Part.find("<matched_part_id>")
        treatments = JSON.parse(template.customisation_data.dig("operation_selection","treatments"))
        # adapt treatments here...
        customer = Organization.find_by!("name ILIKE ?", "%customer name%")
        part = Part.create!(
          customer_id: customer.id,
          part_number: "...",
          part_issue: "...",
          description: "...",
          material: "...",
          specification: "...",
          special_instructions: "...",
          process_type: "hard_anodising",
          customisation_data: {
            "operation_selection" => {
              "locked" => false,
              "treatments" => treatments.to_json,
              "enp_strip_type" => template.customisation_data.dig("operation_selection","enp_strip_type") || "nitric",
              "aerospace_defense" => template.customisation_data.dig("operation_selection","aerospace_defense") || false
            }
          }
        )
        part.auto_lock_for_editing!
        "Created \#{part.part_number} with \#{part.locked_operations.length} operations"

      CRITICAL — eval does not persist local variables between tool calls. Steps 1 and 2
      can be separate calls (read-only). Step 3 must be a single call — create and
      auto_lock_for_editing! together, never split across two calls.

      Always look up the Organization first to get the correct customer_id UUID — never guess it.

      SPEC TO OPERATION_ID GUIDANCE:
      When adapting the operation_id from a template, the spec on the drawing tells you
      what to swap to. Key mappings for chemical conversion:
      - MIL-DTL-5541 Type II (non-hexavalent): IRIDITE_NCP_7_TO_10_MIN or SURTEC_650V
      - MIL-DTL-5541 Type I Class 1A (hexavalent, corrosion resistance): ALOCHROM_1200_CLASS_1A
      - MIL-DTL-5541 Type I Class 3 (hexavalent, electrical conductivity): ALOCHROM_1200_CLASS_3
      For hard anodise operation_ids, follow the naming convention from the matched part
      (e.g. 7XXX_HARD_25_VAT5 for 7xxx alloy, 25μm, vat 5) — query
      Operation.find_matching(process_type: "hard_anodising") only if the matched part's
      operation_id naming convention doesn't make the correct ID obvious.

      MANDATORY TREATMENT ORDERING — FOLLOW THIS EXACTLY, NO EXCEPTIONS:

      When a part requires both hard anodise (Type II or III) and chromate conversion (MIL-DTL-5541):
        ALWAYS in this order:
        1. Chromate conversion applied to the WHOLE part — no masking beforehand
        2. Unjig
        3. Mask the chromate areas (to protect them)
        4. Jig, prep, hard anodise the remaining areas

      MASKING COUNT RULE — CRITICAL:
      For N treatments, there are exactly N-1 masking steps. Never mask before the first treatment.
      The first treatment always goes on the whole part unmasked. Then mask to protect treatment 1
      before applying treatment 2. Then mask to protect treatments 1+2 before treatment 3. Etc.
      Example: 2 treatments = 1 masking step. 3 treatments = 2 masking steps.
      The only exception is where a treatment must be selectively applied on first pass due to
      geometry constraints — this is rare and should only be done if the drawing explicitly
      requires it.

      When a part requires chromic anodise (Type I) alongside any other treatment:
        ALWAYS do chromic anodise FIRST, unmasked across the whole part.
        Then strip it from areas where it is not wanted (it is thin so little material is lost).
        Chromic is "searching" — stopping-off lacquer cannot reliably seal against it, so
        you cannot mask selectively before chromic. Do it first, strip afterwards.

      When a part has two hard anodise thicknesses (e.g. thin ~8–15μm and thick ~46–65μm):
        ALWAYS apply thick hard FIRST with thin-hard areas masked off.
        Then apply thin hard — the thick coating itself acts as masking for this pass.
        These are always two separate sequential operations, never one operation with notes.

      When a drawing references multiple anodise specs by note (e.g. Note 4, Note 5):
        Treat each as a separate sequential treatment unless they are clearly the same
        process type and thickness range.

      VS spec references on Eaton/aerospace drawings map to MIL specs:
        VS 1-3-1-1 = chromic anodise (Type I), VS 1-3-1-4 = hard anodise (Type III),
        VS 1-3-1-176 = chemical conversion. Treat these accordingly.

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
