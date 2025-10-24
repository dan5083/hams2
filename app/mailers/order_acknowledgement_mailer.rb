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

    mail(
      to: recipient_emails,
      subject: "Order Acknowledgement - #{@customer_order.number} - Hard Anodising Surface Treatments Ltd"
    )
  end
end
