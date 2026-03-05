# app/controllers/ai_assistant_controller.rb
class AiAssistantController < ApplicationController
  before_action :require_authentication
  before_action :require_ai_access

  ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages".freeze
  MODEL             = "claude-opus-4-6".freeze

  # Hard blocked — catastrophic / irreversible bulk operations and shell escape.
  # These raise an error and are never executed under any circumstances.
  BLOCKED_PATTERNS = [
    /destroy_all/,
    /delete_all/,
    /drop_table/,
    /truncate/i,
    /\.execute\s*\(/,               # raw SQL via connection.execute
    /`[^`]+`/,                      # shell backticks
    /\bsystem\s*\(/,                # system()
    /\bexec\s*\(/,                  # exec()
    /Kernel\.(system|exec)/,
    /File\.(write|delete|unlink|rename)/,
    /FileUtils\./,
    /IO\.popen/,
    /Open3\./,
  ].freeze

  # Write operations — permitted but logged loudly for audit trail.
  WRITE_PATTERNS = [
    /\.save[!\s(]/,
    /\.update[!\s(]/,
    /\.create[!\s(]/,
    /\.destroy(?!_all)/,
    /\.delete(?!_all)/,
    /\.increment/,
    /\.decrement/,
    /\.toggle/,
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
          CustomerOrder.includes(:customer).where(voided: false).order(date_received: :desc).limit(10).map { |o| { number: o.number, customer: o.customer&.name, open_wos: o.open_works_orders_count } }
          WorksOrder.where(is_open: true).joins(customer_order: :customer).group("organizations.name").count
          Part.where(customer: Organization.find_by(name: "Alutec")).where(enabled: true).pluck(:part_number, :description)
      DESC
      input_schema: {
        type: "object",
        properties: {
          code: {
            type: "string",
            description: "Ruby/ActiveRecord expression to evaluate. Last value is returned."
          }
        },
        required: ["code"]
      }
    }
  ].freeze

  def chat
    messages = params[:messages]

    unless messages.is_a?(Array) && messages.any?
      render json: { error: "No messages provided" }, status: :bad_request
      return
    end

    result = run_agentic_loop(messages)
    render json: { response: result }
  rescue => e
    Rails.logger.error "[AI Assistant] Unhandled error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: { error: "Something went wrong — check Rails logs." }, status: :internal_server_error
  end

  private

  def require_ai_access
    render json: { error: "Access denied." }, status: :forbidden unless Current.user&.can_use_ai_assistant?
  end

  # ── Agentic loop ──────────────────────────────────────────────────────────
  # Calls Claude repeatedly until it produces a final text response,
  # executing any tool_use blocks in between.

  def run_agentic_loop(messages)
    loop_messages = messages.dup
    iterations    = 0

    loop do
      iterations += 1
      raise "Exceeded maximum tool iterations" if iterations > 10

      response    = call_anthropic(loop_messages)
      stop_reason = response["stop_reason"]
      content     = response["content"] || []
      text        = content.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n")

      return text.presence || "Done." if stop_reason == "end_turn"

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

  # ── Anthropic API ─────────────────────────────────────────────────────────

  def call_anthropic(messages)
    uri  = URI(ANTHROPIC_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.read_timeout = 90

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

  # ── System prompt ─────────────────────────────────────────────────────────

  def build_system_prompt
    schema = File.read(Rails.root.join("db", "schema.rb")) rescue "Schema unavailable."

    <<~PROMPT
      You are an internal data assistant embedded in HAMS 2.0 — the management system for
      Hard Anodising Surface Treatments Limited (HASTL).

      You are talking to Daniel Bayliss: the developer, consultant, and minority shareholder.
      He is technical. Do not over-explain. Be direct.

      YOUR CAPABILITY:
      You have one tool — execute_query — which evaluates Ruby/ActiveRecord against the live
      production database. Use it freely. You can call it multiple times per response if needed
      (e.g. search a customer first, then use their ID to fetch orders).
      Always query before answering questions about specific records. Do not guess at IDs or counts.

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

      RESPONSE STYLE:
      - Concise. No hand-holding.
      - Tables or lists for multiple records.
      - Summarise large result sets and offer to drill in.
      - If something looks wrong in the data, say so.
      - Today is #{Date.current.strftime("%A, %d %B %Y")}.

      CURRENT SCHEMA:
      #{schema}
    PROMPT
  end

  # ── Tool dispatch ─────────────────────────────────────────────────────────

  def dispatch_tool(name, input)
    case name
    when "execute_query" then run_query(input["code"].to_s.strip)
    else { error: "Unknown tool: #{name}" }
    end
  end

  def run_query(code)
    return { error: "Empty query." } if code.blank?

    # ── 1. Hard block ──────────────────────────────────────────────────────
    blocked = BLOCKED_PATTERNS.find { |p| code.match?(p) }
    if blocked
      Rails.logger.warn "[AI Assistant] BLOCKED — user: #{Current.user&.email_address} | pattern: #{blocked.source} | code: #{code}"
      return {
        blocked: true,
        reason: "This operation is not permitted (matched: #{blocked.source})",
        code: code
      }
    end

    # ── 2. Classify and log ────────────────────────────────────────────────
    is_write = WRITE_PATTERNS.any? { |p| code.match?(p) }

    if is_write
      Rails.logger.warn "[AI Assistant] WRITE — user: #{Current.user&.email_address} | code: #{code}"
    else
      Rails.logger.info  "[AI Assistant] READ  — user: #{Current.user&.email_address} | code: #{code}"
    end

    # ── 3. Execute ────────────────────────────────────────────────────────
    # Writes run in a normal transaction (commits).
    # Reads run in a transaction that always rolls back — belt and braces
    # to prevent accidental mutations from pure-looking queries.
    result = if is_write
      ActiveRecord::Base.transaction { eval(code) } # rubocop:disable Security/Eval
    else
      outcome = nil
      ActiveRecord::Base.transaction do
        outcome = eval(code) # rubocop:disable Security/Eval
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
    Rails.logger.error "[AI Assistant] Query error: #{e.class} — #{e.message} | Code: #{code}"
    { error: e.class.to_s, detail: e.message }
  end

  def serialise(value)
    case value
    when ActiveRecord::Relation  then value.as_json
    when ActiveRecord::Base      then value.as_json
    when Array                   then value.map { |v| v.respond_to?(:as_json) ? v.as_json : v }
    when Hash, Numeric, String,
         TrueClass, FalseClass,
         NilClass                then value
    else
      value.respond_to?(:as_json) ? value.as_json : value.to_s
    end
  end
end
