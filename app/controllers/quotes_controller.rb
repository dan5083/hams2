# app/controllers/quotes_controller.rb
#
# Quotes are raised by the assistant (QuoteService.create_from_request); this
# controller lists them, shows one (HTML or the PDF the customer gets), and
# offers the same send / status actions as the assistant's send! step, for
# when someone wants to re-send or close one off by hand.
class QuotesController < ApplicationController
  before_action :set_quote, only: [:show, :send_email, :update_status]

  def index
    @quotes = Quote.includes(:customer, :created_by).recent
    @quotes = @quotes.where(status: params[:status]) if Quote::STATUSES.include?(params[:status])
    @quotes = @quotes.where(customer_id: params[:customer_id]) if params[:customer_id].present?
    @quotes = @quotes.page(params[:page]).per(25)
    @customers = Organization.enabled.order(:name)
  end

  def show
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

  # Re-send (or first send, if the assistant stopped short). Optional `to`
  # overrides the enquirer address.
  def send_email
    result = QuoteService.send!(quote_id: @quote.id, to: params[:to].presence)
    if result[:success]
      redirect_to @quote, notice: "✅ #{result[:message]}"
    else
      redirect_to @quote, alert: "❌ #{result[:error]}"
    end
  end

  def update_status
    status = params[:status].to_s
    unless Quote::STATUSES.include?(status)
      redirect_to @quote, alert: "Unknown status."
      return
    end
    @quote.update!(status: status)
    redirect_to @quote, notice: "#{@quote.display_name} marked #{status}."
  end

  private

  def set_quote
    @quote = Quote.includes(quote_items: :part).find(params[:id])
  end
end
