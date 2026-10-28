# app/controllers/quotes_controller.rb
#
# Quotes have two halves:
#
#   Workbench (new → create → build → rerun → finalise): upload drawings and
#   the enquiry, the assistant proposes part configuration + prices +
#   questions (QuoteProposalJob), the reviewer edits/answers on the build
#   page and either re-runs with answers or saves. Nothing exists in HAMS
#   beyond the Quote row until Save.
#
#   Saved quote (show / edit / update / send_email / update_status): parts +
#   items exist; edit changes header + lines by hand (no assistant) at any
#   stage; send emails the PDF and drawings; won/lost by hand.
class QuotesController < ApplicationController
  before_action :set_quote, only: [:show, :build, :rerun, :finalise, :edit, :update, :send_email, :update_status]

  def index
    @quotes = Quote.includes(:customer, :created_by).recent
    @quotes = @quotes.where(status: params[:status]) if Quote::STATUSES.include?(params[:status])
    @quotes = @quotes.where(customer_id: params[:customer_id]) if params[:customer_id].present?
    @quotes = @quotes.page(params[:page]).per(25)
    @customers = Organization.enabled.order(:name)
  end

  def show
    redirect_to build_quote_path(@quote) and return if @quote.in_workbench?
    respond_to do |format|
      format.html
      format.pdf do
        html = render_to_string(template: "quotes/pdf", formats: [:html], layout: false)
        pdf  = Grover.new(html, format: "A4", margin: { top: "1cm", bottom: "1cm", left: "1cm", right: "1cm" },
                          print_background: true, prefer_css_page_size: true, wait_until: "domcontentloaded").to_pdf
        send_data pdf, filename: "#{@quote.display_name}.pdf", type: "application/pdf", disposition: "inline"
      end
    end
  end

  # ── Workbench ──────────────────────────────────────────────────────────

  def new
    @quote = Quote.new(valid_until: Date.current + Quote::VALIDITY_DAYS.days)
  end

  def create
    files    = Array(params.dig(:quote, :drawings)).reject(&:blank?)
    if files.empty?
      @quote = Quote.new(quote_params)
      @quote.errors.add(:base, "Attach at least one drawing or enquiry document.")
      render :new, status: :unprocessable_entity and return
    end

    @quote = Quote.new(quote_params.merge(status: "proposing", created_by: Current.user))
    @quote.drawings = files.map { |f| upload_drawing(f) }
    @quote.save!
    QuoteProposalJob.perform_later(@quote.id)
    redirect_to build_quote_path(@quote)
  rescue => e
    Rails.logger.error "quotes#create failed: #{e.message}"
    @quote ||= Quote.new(quote_params)
    @quote.errors.add(:base, e.message)
    render :new, status: :unprocessable_entity
  end

  def build
    respond_to do |format|
      format.html do
        redirect_to @quote and return unless @quote.in_workbench?
      end
      format.json { render json: { status: @quote.status, error: @quote.proposal_error, updated_at: @quote.updated_at } }
    end
  end

  # Post the reviewer's answers (and any edits) back to the assistant.
  def rerun
    resolve_customer!
    attrs = { answers: (params[:answers] || {}).to_unsafe_h.reject { |_, v| v.blank? },
              proposal: merged_proposal, status: "proposing", proposal_error: nil }
    # The drawing description is the assistant's only view of an ITAR
    # drawing, so a correction here must reach the re-run.
    attrs[:drawing_description] = params.dig(:form, :drawing_description) if params.dig(:form, :drawing_description)
    # The per-piece floor is read from the quote by the prompt and the job's
    # post-processing, so it must be on the row before the job runs.
    attrs[:minimum_per_piece] = params.dig(:form, :minimum_per_piece) if params.dig(:form, :minimum_per_piece).present?
    @quote.update!(attrs)
    QuoteProposalJob.perform_later(@quote.id)
    redirect_to build_quote_path(@quote)
  rescue => e
    # Customer creation (Xero) is the only thing above that can fail on
    # user input; show it on the workbench rather than a 500.
    Rails.logger.error "quotes#rerun (#{@quote.display_name}) failed: #{e.class}: #{e.message}"
    redirect_to build_quote_path(@quote), alert: "❌ Not re-run: #{e.message}"
  end

  # Create parts + items from the reviewed form.
  def finalise
    return rerun if params[:intent] == "rerun" # same form, same CSRF token — see build.html.erb
    resolve_customer!
    raise "Pick a customer before saving — the assistant couldn't match one. Type the HAMS name, or tick 'create it' to add a new customer." unless @quote.customer

    # The form is free-shaped (parts keyed by proposal key, arbitrary
    # treatment JSON), so it can't be strong-params-permitted field by field;
    # QuoteService.finalise! is the validation layer.
    # Keep the answers on record even though Save doesn't act on them (only
    # Re-run does) — they explain the cards to whoever reads the quote later.
    @quote.update!(answers: (params[:answers] || {}).to_unsafe_h.reject { |_, v| v.blank? }) if params[:answers].present?
    result = QuoteService.finalise!(@quote, params.require(:form).to_unsafe_h)
    created = result[:parts_created]
    redirect_to @quote, notice: "✅ #{@quote.display_name} saved#{created.any? ? " — created #{created.map(&:display_name).join(', ')} with #{@quote.drawings.length} drawing(s) attached" : ''}. Send it from here when you're happy."
  rescue => e
    Rails.logger.error "quotes#finalise (#{@quote.display_name}) failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to build_quote_path(@quote), alert: "❌ Not saved: #{e.message}"
  end

  # ── Saved quote ────────────────────────────────────────────────────────

  # Hand edits at any stage. Nothing here talks to the assistant: to have it
  # re-price, raise a new quote.
  def edit
    redirect_to build_quote_path(@quote) and return if @quote.in_workbench?
  end

  def update
    QuoteService.edit!(@quote, params.require(:form).to_unsafe_h)
    notice = "✅ #{@quote.display_name} updated."
    notice += " It was sent on #{@quote.sent_at.strftime('%d/%m/%Y')} — re-send it if the customer should see the change." if @quote.sent_at
    redirect_to @quote, notice: notice
  rescue => e
    Rails.logger.error "quotes#update (#{@quote.display_name}) failed: #{e.class}: #{e.message}"
    redirect_to edit_quote_path(@quote), alert: "❌ Not saved: #{e.message}"
  end

  def send_email
    result = QuoteService.send!(quote_id: @quote.id, to: params[:to].presence)
    redirect_to @quote, result[:success] ? { notice: "✅ #{result[:message]}" } : { alert: "❌ #{result[:error]}" }
  end

  def update_status
    status = params[:status].to_s
    redirect_to @quote, alert: "Unknown status." and return unless %w[draft sent won lost].include?(status)
    @quote.update!(status: status)
    redirect_to @quote, notice: "#{@quote.display_name} marked #{status}."
  end

  private

  def set_quote
    @quote = Quote.includes(quote_items: :part).find(params[:id])
  end

  def quote_params
    params.require(:quote).permit(:enquiry, :valid_until, :itar, :drawing_description)
  end

  # Cloudinary for HAMS (thumbnails, parts, the email); Anthropic Files for
  # the assistant, uploaded once here so QuoteProposalJob references it by id
  # on every run instead of fetching and base64-encoding it. An ITAR quote's
  # drawings never go to Anthropic — Quote#drawings_for_assistant is [] and
  # there is no anthropic_file_id to find.
  def upload_drawing(file)
    r = CloudinaryService.upload_file(file, "quotes", filename_prefix: "qt")
    drawing = {
      "cloudinary_public_id" => r[:public_id], "cloudinary_url" => r[:secure_url],
      "original_filename" => r[:filename], "file_size_bytes" => r[:size],
      "content_type" => r[:content_type], "uploaded_at" => Time.current.iso8601
    }
    unless @quote.itar?
      # Read by path, not through the upload object's handle: the cloudinary
      # gem closes any IO it is handed, and a closed Tempfile is still on
      # disk until the request ends. Failure here must not lose the quote -
      # QuoteProposalJob#drawing_file_id uploads any drawing without an id.
      begin
        path = file.respond_to?(:tempfile) ? file.tempfile.path : file.path
        drawing["anthropic_file_id"] = AnthropicFiles.upload(File.binread(path), filename: r[:filename], media_type: r[:content_type])
      rescue => e
        Rails.logger.warn "quotes#create: Anthropic Files upload of #{r[:filename]} failed, job will retry: #{e.message}"
      end
    end
    drawing
  end

  # The build page posts form[customer_id] (hidden, from the proposal),
  # form[customer_name] (editable) and form[create_customer] (tick box). A
  # changed name wins over the id. If nothing matches and the box is ticked,
  # the customer is created in Xero and mirrored into HAMS — a customer that
  # exists only in HAMS could never be invoiced, so there is no HAMS-only
  # path. Called from both rerun and finalise, so a customer created on
  # Re-run is the CUSTOMER block the assistant sees on its next pass.
  def resolve_customer!
    form = (params[:form] || {}).to_unsafe_h
    name = form["customer_name"].to_s.strip
    org  = Organization.enabled.find_by("name ILIKE ?", name) if name.present?
    org ||= Organization.find_by(id: form["customer_id"]) if form["customer_id"].present?
    if org.nil? && form["create_customer"] == "1"
      raise "Enter the customer's name to create it." if name.blank?
      org = XeroContact.create_customer!(name: name, email: form["enquirer_email"].presence)
      Rails.logger.info "quotes#resolve_customer!: created customer #{org.name} (#{org.id}) via Xero for #{@quote.display_name}"
    end
    @quote.update!(customer: org) if org && org != @quote.customer
  end

  # On re-run, carry the reviewer's edits into the proposal so the model
  # refines what they left rather than its own earlier draft.
  def merged_proposal
    form = (params[:form] || {}).to_unsafe_h.deep_stringify_keys
    prop = (@quote.proposal || {}).deep_dup
    %w[title summary notes enquirer_name enquirer_email].each { |k| prop[k] = form[k] if form.key?(k) }
    prop["customer_id"]   = @quote.customer_id if @quote.customer_id
    prop["customer_name"] = @quote.customer&.name if @quote.customer
    if form["parts"].is_a?(Hash)
      prop["parts"] = Array(prop["parts"]).map do |p|
        f = form["parts"][p["key"]] or next p
        p.merge(f.slice("part_number", "part_issue", "description", "specification", "material", "specified_thicknesses",
                        "process_type", "jigging_location", "jig_type", "existing_part_id"))
         .merge("drawing_indexes" => f["drawing_indexes"].to_s.split(",").map(&:strip).reject(&:blank?).map(&:to_i))
         .merge("treatments" => (JSON.parse(f["treatments"]) rescue p["treatments"]))
      end
    end
    if form["lines"].is_a?(Hash)
      prop["lines"] = form["lines"].values.sort_by { |l| l["position"].to_i }.map { |l|
        l.slice("part_key", "description", "reasoning")
         .merge("quantity" => l["quantity"].to_i, "unit_amount" => l["unit_amount"].to_f,
                "components" => (JSON.parse(l["components"].to_s) rescue []))
      }
    end
    prop
  end
end
