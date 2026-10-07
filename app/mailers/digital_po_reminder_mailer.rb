# app/mailers/digital_po_reminder_mailer.rb
#
# "Please email your POs to orders@" - sent by DigitalPoNudge when an
# acknowledged order's PO arrived on paper, via an individual's inbox, or
# forwarded by one of us. Same cc/reply-to convention as the acknowledgement:
# the reviewer who signed off is the person any reply should reach.
class DigitalPoReminderMailer < ApplicationMailer
  ORDERS_ADDRESS = "orders@hardanodisingstl.com".freeze

  def remind(customer_order, origin:, to:, cc: nil)
    @customer_order = customer_order
    @customer       = customer_order.customer
    @origin         = origin.to_sym
    @orders_address = ORDERS_ADDRESS

    attach_inline_logo

    cc_list = Array(cc).map { |e| e.to_s.strip }.reject(&:blank?).uniq - Array(to)

    mail(
      to:       to,
      cc:       cc_list.presence,
      reply_to: cc_list.first.presence,
      subject:  "Sending us purchase orders - #{@customer_order.number} - Hard Anodising Surface Treatments Ltd"
    )
  end
end
