# app/mailers/customer_order_mailer.rb
#
# Sent automatically when a customer order becomes fully released (trigger:
# WorksOrder#notify_buyer_if_order_complete). Tells the buyer the order is
# either ready to collect (no carriage charges) or about to be dispatched by
# courier (carriage charge present on any works order), and attaches the
# Certificate of Conformity PDF for every release note on the order.
#
# The attached PDFs are rendered from the same release_notes/pdf template as
# the web version, but with for_email: true, which strips the Proof of
# Collection page and the NADCAP operator copy page — the emailed document is
# the CofC only.
class CustomerOrderMailer < ApplicationMailer
  # The order_ready templates are complete HTML/text documents (matching the
  # order acknowledgement style), so skip the shared mailer layout.
  layout false

  COMPANY_NAME    = "Hard Anodising Surface Treatments Ltd".freeze
  TRADING_ADDRESS = "Firs Industrial Estate, Rickets Close\nKidderminster, DY11 7QN".freeze

  def order_ready(customer_order)
    @customer_order     = customer_order
    @customer           = customer_order.customer
    @by_courier         = customer_order.carriage_charge_present?
    @works_orders       = customer_order.works_orders.active.includes(:part).order(:number)
    @release_note_count = customer_order.email_release_notes.size

    recipients = @customer.buyer_emails
    if recipients.empty?
      Rails.logger.warn "order_ready: no buyer or contact email for #{@customer.name} " \
                        "(CO #{customer_order.number}) — email not sent"
      return
    end

    attach_certificates_of_conformity
    attach_inline_logo

    mail(
      to: recipients,
      subject: subject_line
    )
  end

  private

  # Embedded as an inline (cid:) attachment because email clients block
  # remote images by default; referenced in the view via attachments['logo.png'].url
  def attach_inline_logo
    logo_path = Rails.root.join('app', 'assets', 'images', 'logo-with-company-name.png')
    attachments.inline['logo.png'] = File.read(logo_path) if File.exist?(logo_path)
  rescue StandardError => e
    Rails.logger.warn "order_ready: could not attach logo: #{e.message}"
  end

  def subject_line
    if @by_courier
      "Your order #{@customer_order.number} is complete and will be dispatched by courier"
    else
      "Your order #{@customer_order.number} is ready for collection"
    end
  end

  def attach_certificates_of_conformity
    @customer_order.email_release_notes.each do |release_note|
      attachments["CofC_RN#{release_note.number}.pdf"] = {
        mime_type: 'application/pdf',
        content: certificate_pdf(release_note)
      }
    rescue StandardError => e
      # A single bad PDF shouldn't kill the whole notification; log and carry on.
      Rails.logger.error "order_ready: failed to render CofC for RN#{release_note.number}: #{e.message}"
    end
  end

  # Mirrors ReleaseNotesController#pdf exactly (same template, same Grover
  # options), except for_email: true. Passed as both assigns and locals
  # because the template reads @release_note while the controller also
  # supplies locals — keep both in sync with the controller action.
  def certificate_pdf(release_note)
    html = ApplicationController.render(
      template: 'release_notes/pdf',
      layout: false,
      assigns: {
        release_note: release_note,
        company_name: COMPANY_NAME,
        trading_address: TRADING_ADDRESS
      },
      locals: {
        release_note: release_note,
        company_name: COMPANY_NAME,
        trading_address: TRADING_ADDRESS,
        for_email: true
      }
    )

    Grover.new(
      html,
      format: 'A4',
      margin: { top: '1cm', bottom: '1cm', left: '1cm', right: '1cm' },
      print_background: true,
      prefer_css_page_size: true
    ).to_pdf
  end
end
