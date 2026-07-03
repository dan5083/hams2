# app/mailers/order_acknowledgement_mailer.rb
class OrderAcknowledgementMailer < ApplicationMailer
  def order_confirmation(customer_order, works_orders)
    @customer_order = customer_order
    @works_orders = works_orders
    @customer = customer_order.customer

    # Calculate totals
    @total_quantity = @works_orders.sum(&:quantity)
    @total_value = @works_orders.sum(&:lot_price)

    # Get unique customer references if any
    @customer_references = @works_orders.map(&:customer_reference).compact.uniq.reject(&:blank?)

    # Get buyer emails (returns array, falls back to primary contact if no buyers)
    recipient_emails = @customer.buyer_emails

    attach_inline_logo

    mail(
      to: recipient_emails,
      subject: "Order Acknowledgement - #{@customer_order.number} - Hard Anodising Surface Treatments Ltd"
    )
  end

  private

  # Embedded as an inline (cid:) attachment because email clients block remote
  # images by default; the view renders it via attachments['logo.png'].url and
  # falls back to a text header when the attachment is absent.
  def attach_inline_logo
    logo_path = Rails.root.join('app', 'assets', 'images', 'logo-with-company-name.png')
    attachments.inline['logo.png'] = File.read(logo_path) if File.exist?(logo_path)
  rescue StandardError => e
    Rails.logger.warn "order_confirmation: could not attach logo: #{e.message}"
  end
end
