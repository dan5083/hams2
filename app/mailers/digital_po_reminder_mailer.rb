# app/mailers/digital_po_reminder_mailer.rb
#
# "Please email your POs to orders@" - sent by DigitalPoNudge when an
# acknowledged order's PO arrived on paper, via an individual's inbox, or
# forwarded by one of us. Reply-to is orders@ so a "that's our purchasing
# system, please add it" reply lands in the shared mailbox.
class DigitalPoReminderMailer < ApplicationMailer
  ORDERS_ADDRESS = "orders@hardanodisingstl.com".freeze

  def remind(customer_order, origin:, to:)
    @customer_order = customer_order
    @customer       = customer_order.customer
    @origin         = origin.to_sym
    @orders_address = ORDERS_ADDRESS

    attach_inline_logo

    mail(
      to:       to,
      reply_to: ORDERS_ADDRESS,
      subject:  "Sending us purchase orders - #{@customer_order.number} - Hard Anodising Surface Treatments Ltd"
    )
  end
end
