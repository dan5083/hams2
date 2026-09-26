# app/models/inbound_purchase_order.rb
#
# One row per email that arrived at orders@ (via Mailgun store-and-notify).
# The controller records it, PoIntakeJob fetches the attachments into
# Cloudinary and asks the assistant to read the PO, and the outcome lands in
# `proposal` / `status` for a human to act on. Nothing is booked into HAMS
# until someone calls #create_order! (console for now, review page later).
class InboundPurchaseOrder < ApplicationRecord
  belongs_to :ai_assistant_request, optional: true
  belongs_to :customer_order,       optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  STATUSES = %w[received fetching analysing needs_review already_on_file ignored error booked dismissed].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :mailgun_message_id, presence: true, uniqueness: true

  scope :open,   -> { where(status: %w[received fetching analysing needs_review]) }
  scope :recent, -> { order(received_at: :desc) }

  USABLE_CONTENT_TYPES = %w[application/pdf image/jpeg image/png image/webp image/gif].freeze

  def usable_attachments
    attachments.select { |a| USABLE_CONTENT_TYPES.include?(a["content_type"].to_s.downcase) }
  end

  def pdf_attachments
    attachments.select { |a| a["content_type"].to_s.downcase == "application/pdf" }
  end

  def image_attachments
    attachments.select { |a| a["content_type"].to_s.downcase.start_with?("image/") }
  end

  # Out-of-office, bounces, read receipts, mailing-list noise. Cheap header /
  # subject checks — not worth a Claude call.
  def auto_reply?
    h = headers.transform_keys(&:downcase)
    return true if h["auto-submitted"].present? && h["auto-submitted"].to_s.downcase != "no"
    return true if h["x-auto-response-suppress"].present?
    return true if h["precedence"].to_s.downcase.in?(%w[bulk junk list auto_reply])
    return true if sender.to_s.match?(/\A(no-?reply|mailer-daemon|postmaster)@/i)
    subject.to_s.match?(/\b(automatic reply|out of office|autoreply|undeliverable|delivery status notification|read:)\b/i)
  end

  # ---------------------------------------------------------------------------
  # Human approval: turn the assistant's proposal into a CustomerOrder and
  # attach the PO document. Works orders are NOT created here yet — that's
  # the next step once the review flow has proven itself.
  #
  #   ipo.create_order!(reviewed_by: User.find_by(email_address: "julia@..."))
  #
  # Pass overrides if the assistant misread something:
  #   ipo.create_order!(reviewed_by: u, customer_id: 42, number: "PO-1234")
  # ---------------------------------------------------------------------------
  def create_order!(reviewed_by:, customer_id: nil, number: nil, date_received: nil, attachment_index: nil)
    raise "Already linked to CustomerOrder #{customer_order_id}" if customer_order_id.present?

    customer_id ||= proposal["customer_id"]
    number      ||= proposal["po_number"]
    raise "No customer_id — pass one explicitly" if customer_id.blank?
    raise "No PO number — pass one explicitly"   if number.blank?

    date_received ||= proposal["order_date"].presence && Date.parse(proposal["order_date"]) rescue nil

    transaction do
      co = CustomerOrder.find_by(customer_id: customer_id, number: number)
      if co&.po_attached?
        raise "CustomerOrder #{co.id} already exists with a PO attached"
      end

      co ||= CustomerOrder.create!(
        { customer_id: customer_id, number: number, date_received: date_received }.compact
      )

      PurchaseOrderService.attach_from_inbound(
        customer_order: co,
        inbound_purchase_order: self,
        attachment_index: attachment_index
      )

      update!(customer_order: co, status: "booked", reviewed_by: reviewed_by, reviewed_at: Time.current)
      co
    end
  end

  def dismiss!(reviewed_by:, reason: nil)
    update!(status: "dismissed", reviewed_by: reviewed_by, reviewed_at: Time.current,
            summary: [summary, reason].compact.join(" — "))
  end
end
