# app/mailers/order_acknowledgement_mailer.rb
class OrderAcknowledgementMailer < ApplicationMailer
  def order_confirmation(customer_order, works_orders)
    @customer_order = customer_order
    @works_orders = works_orders  # Remove .includes() - these are already loaded objects
    @customer = customer_order.customer

    # Calculate totals
    @total_quantity = @works_orders.sum(&:quantity)
    @total_value = @works_orders.sum(&:lot_price)

    # Get unique customer references if any
    @customer_references = @works_orders.map(&:customer_reference).compact.uniq.reject(&:blank?)

    mail(
      to: @customer.contact_email,
      subject: "Order Acknowledgement - #{@customer_order.number} - Hard Anodising Surface Treatments Ltd"
    )
  end
end
