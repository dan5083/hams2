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
#   Saved quote (show / send_email / update_status): parts + items exist;
#   send emails the PDF and drawings; won/lost by hand.
class QuotesController < ApplicationController
  before_action :set_quote, only: [:show, :build, :rerun, :finalise, :send_email, :update_status]

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
    @quote = Quote.new(valid_until: Date.current + 30.days)
    @customers = Organization.enabled.order(:name)
  end

  def create
    customer = Organization.find(params.dig(:quote, :customer_id))
    files    = Array(params.dig(:quote, :drawings)).reject(&:blank?)
    if files.empty?
      @quote = Quote.new(quote_params); @customers = Organization.enabled.order(:name)
      @quote.errors.add(:base, "Attach at least one drawing or enquiry document.")
      render :new, status: :unprocessable_entity and return
    end

    @quote = Quote.new(quote_params.merge(customer: customer, status: "proposing", created_by: Current.user))
    @quote.drawings = files.map { |f| upload_drawing(f, customer) }
    @quote.save!
    QuoteProposalJob.perform_later(@quote.id)
    redirect_to build_quote_path(@quote)
  rescue => e
    Rails.logger.error "quotes#create failed: #{e.message}"
    @quote ||= Quote.new(quote_params); @customers = Organization.enabled.order(:name)
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
    @quote.update!(answers: (params[:answers] || {}).to_unsafe_h.reject { |_, v| v.blank? },
                   proposal: merged_proposal, status: "proposing", proposal_error: nil)
    QuoteProposalJob.perform_later(@quote.id)
    redirect_to build_quote_path(@quote)
  end

  # Create parts + items from the reviewed form.
  def finalise
    # The form is free-shaped (parts keyed by proposal key, arbitrary
    # treatment JSON), so it can't be strong-params-permitted field by field;
    # QuoteService.finalise! is the validation layer.
    result = QuoteService.finalise!(@quote, params.require(:form).to_unsafe_h)
    created = result[:parts_created]
    redirect_to @quote, notice: "✅ #{@quote.display_name} saved#{created.any? ? " — created #{created.map(&:display_name).join(', ')} with #{@quote.drawings.length} drawing(s) attached" : ''}. Send it from here when you're happy."
  rescue => e
    Rails.logger.error "quotes#finalise (#{@quote.display_name}) failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    redirect_to build_quote_path(@quote), alert: "❌ Not saved: #{e.message}"
  end

  # ── Saved quote ────────────────────────────────────────────────────────

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
    params.require(:quote).permit(:customer_id, :enquirer_name, :enquirer_email, :enquiry, :valid_until)
  end

  def upload_drawing(file, customer)
    r = CloudinaryService.upload_file(file, "quotes/#{customer.name.parameterize}", filename_prefix: "qt")
    {
      "cloudinary_public_id" => r[:public_id], "cloudinary_url" => r[:secure_url],
      "original_filename" => r[:filename], "file_size_bytes" => r[:size],
      "content_type" => r[:content_type], "uploaded_at" => Time.current.iso8601
    }
  end

  # On re-run, carry the reviewer's edits into the proposal so the model
  # refines what they left rather than its own earlier draft.
  def merged_proposal
    form = (params[:form] || {}).to_unsafe_h.deep_stringify_keys
    prop = (@quote.proposal || {}).deep_dup
    %w[title summary notes enquirer_name enquirer_email].each { |k| prop[k] = form[k] if form.key?(k) }
    if form["parts"].is_a?(Hash)
      prop["parts"] = Array(prop["parts"]).map do |p|
        f = form["parts"][p["key"]] or next p
        p.merge(f.slice("part_number", "part_issue", "description", "specification", "material", "specified_thicknesses",
                        "process_type", "jigging_location", "jig_type", "existing_part_id"))
         .merge("treatments" => (JSON.parse(f["treatments"]) rescue p["treatments"]))
      end
    end
    if form["lines"].is_a?(Hash)
      prop["lines"] = form["lines"].values.sort_by { |l| l["position"].to_i }.map { |l|
        l.slice("part_key", "description", "reasoning").merge("quantity" => l["quantity"].to_i, "unit_amount" => l["unit_amount"].to_f)
      }
    end
    prop
  end
end
