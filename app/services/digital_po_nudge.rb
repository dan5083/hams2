# app/services/digital_po_nudge.rb
#
# Asks a customer to send purchase orders digitally to orders@ when the one
# we've just acknowledged didn't arrive that way:
#
#   :paper     - photographed off the copy that came with the parts
#                (po_document source "scanned_images")
#   :manual    - a PDF someone uploaded by hand, i.e. it was emailed to an
#                individual's inbox (source "upload" from the edit form, "pdf"
#                from the assistant)
#   :forwarded - it did reach orders@, but not from a domain we hold for the
#                customer (buyers + Xero contact), so somebody forwarded it on
#
# A PO the customer emailed to orders@ themselves is left alone. Fires at the
# moment the PO is attached: from InboundPurchaseOrder#book_order! for email
# (passing the inbound row, since it isn't linked to the order yet) and from
# a CustomerOrder after_commit on po_document for everything else.
# Deliberately NOT throttled: every paper/forwarded order gets one until they
# change. The acknowledgement no longer carries the generic "send orders to
# orders@" note - this is the targeted replacement.
#
#   DigitalPoNudge.deliver_if_needed(customer_order)
#   DigitalPoNudge.deliver_if_needed(customer_order, inbound: ipo)
#   DigitalPoNudge.new(customer_order).origin_of_po   # console: why/why not
class DigitalPoNudge
  # "From:" line in a forwarded body, quoted or not. Outlook writes
  # "From: Jo Bloggs <jo@x.com>" or "[mailto:jo@x.com]"; EMAIL pulls the
  # address out of either.
  FORWARDED_FROM = /^\s*>?\s*(?:From|Von|De)\s*:\s*(.+)$/i
  EMAIL          = /[\w.+-]+@[\w-]+(?:\.[\w-]+)+/

  Origin = Struct.new(:kind, :original_sender, keyword_init: true)

  def self.deliver_if_needed(customer_order, inbound: nil)
    new(customer_order, inbound: inbound).deliver_if_needed
  end

  def initialize(customer_order, inbound: nil)
    @co       = customer_order
    @customer = customer_order.customer
    @ipo      = inbound
  end

  def deliver_if_needed
    origin = origin_of_po
    return skip("PO came from the customer digitally (or no PO attached)") if origin.nil?

    to = recipients(origin)
    return skip("no email address for #{@customer.name}") if to.empty?

    DigitalPoReminderMailer.remind(@co, origin: origin.kind, to: to).deliver_later
    Rails.logger.info "[DigitalPoNudge] #{@co.display_name}: #{origin.kind} → #{to.join(', ')}"
    true
  end

  # nil when there's nothing to nudge about.
  def origin_of_po
    case @co.po_document.to_h["source"]
    when "scanned_images" then Origin.new(kind: :paper)
    when "upload", "pdf"  then Origin.new(kind: :manual)
    when "email"          then email_origin
    end
  end

  # Domains we hold for this customer: buyers plus the Xero contact.
  def customer_domains
    @customer_domains ||= (@customer.buyers.enabled.pluck(:email) + [@customer.contact_email])
                            .filter_map { |e| domain_of(e) }.uniq
  end

  private

  def email_origin
    ipo = @ipo || InboundPurchaseOrder.find_by(customer_order_id: @co.id)
    return nil unless ipo
    return skip_nil("no domains on file for #{@customer.name}, can't tell who sent it") if customer_domains.empty?
    return nil if customer_domain?(ipo.sender)

    # Not from the customer's domain, so one of us (or someone's personal
    # address) sent it on. The quoted From:, if we can find it, is who to tell.
    Origin.new(kind: :forwarded, original_sender: forwarded_from(ipo))
  end

  # The person who sent it to the wrong place is the one to tell; failing
  # that, the buyers (which falls back to the Xero contact email).
  def recipients(origin)
    emails = [origin.original_sender].compact
    emails = @customer.buyer_emails if emails.empty?
    emails.map { |e| e.to_s.strip.downcase }.reject(&:blank?).uniq
  end

  def domain_of(email)
    email.to_s[EMAIL].to_s.split("@").last&.downcase.presence
  end

  def customer_domain?(email)
    customer_domains.include?(domain_of(email))
  end

  # First quoted "From:" in the body that IS one of the customer's addresses.
  def forwarded_from(ipo)
    ipo.body_plain.to_s.scan(FORWARDED_FROM).flatten.each do |line|
      email = line[EMAIL]
      return email.downcase if email && customer_domain?(email)
    end
    nil
  end

  def skip(reason)
    Rails.logger.info "[DigitalPoNudge] #{@co.display_name}: skipped - #{reason}"
    false
  end

  def skip_nil(reason)
    skip(reason)
    nil
  end
end
