# app/mailers/quote_mailer.rb
#
# Sends a quotation to the enquirer, with the quote as a PDF and every
# drawing held on the quoted parts attached. Cc's the person who raised it
# (so the thread lands in their inbox) and QUOTES_CC if set; reply-to is
# that person, not noreply@.
class QuoteMailer < ApplicationMailer
  layout false

  COMPANY_NAME    = "Hard Anodising Surface Treatments Ltd".freeze
  TRADING_ADDRESS = "Firs Industrial Estate, Rickets Close\nKidderminster, DY11 7QN".freeze

  def quote_email(quote, cc: [])
    @quote    = quote
    @customer = quote.customer
    @items    = quote.quote_items.includes(:part)
    @sender   = quote.created_by

    cc_list = (Array(cc) + [@sender&.email_address, ENV["QUOTES_CC"]]).compact.map(&:strip).reject(&:blank?).uniq
    cc_list -= [quote.enquirer_email]

    attach_inline_logo
    attachments["#{quote.display_name}_#{quote.customer.name.parameterize}.pdf"] = {
      mime_type: "application/pdf", content: quote_pdf(quote)
    }
    attach_drawings

    mail(
      to: quote.enquirer_email,
      cc: cc_list.presence,
      reply_to: @sender&.email_address.presence,
      subject: "Quotation #{quote.display_name} from #{COMPANY_NAME}#{" — #{quote.title}" if quote.title.present?}"
    )
  end

  private

  def attach_inline_logo
    logo_path = Rails.root.join("app", "assets", "images", "logo-with-company-name.png")
    attachments.inline["logo.png"] = File.read(logo_path) if File.exist?(logo_path)
  rescue StandardError => e
    Rails.logger.warn "quote_email: could not attach logo: #{e.message}"
  end

  # Drawings live on Cloudinary; pull the bytes so the customer gets real
  # attachments rather than links. A single bad file is logged, not fatal.
  def attach_drawings
    @quote.attachable_part_files.each do |ref|
      part, i = ref[:part], ref[:index]
      file = part.files[i]
      url  = file["cloudinary_url"]
      next if url.blank?
      body = fetch(url) or next
      name = file["original_filename"].presence || "drawing_#{i + 1}"
      name = "#{part.display_name}_#{name}".gsub(/[^\w.\-]+/, "_")
      attachments[name] = { mime_type: file["content_type"].presence || "application/octet-stream", content: body }
    rescue StandardError => e
      Rails.logger.error "quote_email: failed to attach drawing #{i} of #{part.display_name}: #{e.message}"
    end
  end

  def fetch(url, limit = 3)
    uri = URI(url)
    res = Net::HTTP.get_response(uri)
    if res.is_a?(Net::HTTPRedirection) && limit > 0
      fetch(res["location"], limit - 1)
    elsif res.is_a?(Net::HTTPSuccess)
      res.body
    end
  end

  def quote_pdf(quote)
    html = ApplicationController.render(
      template: "quotes/pdf", layout: false,
      assigns: { quote: quote, company_name: COMPANY_NAME, trading_address: TRADING_ADDRESS }
    )
    Grover.new(html, format: "A4", margin: { top: "1cm", bottom: "1cm", left: "1cm", right: "1cm" },
               print_background: true, prefer_css_page_size: true, wait_until: "domcontentloaded").to_pdf
  end
end
