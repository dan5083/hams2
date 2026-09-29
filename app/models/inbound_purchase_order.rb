# app/models/inbound_purchase_order.rb
#
# One row per email that arrived at orders@ (via a Mailgun forward() route).
# The controller records it and parks the attachments in Cloudinary,
# PoIntakeJob asks the assistant to read the PO, and the outcome lands in
# `proposal` / `status`. A clean proposal is booked on the spot by
# #create_order!; the rest wait for a reviewer to call it.
class InboundPurchaseOrder < ApplicationRecord
  belongs_to :ai_assistant_request, optional: true
  belongs_to :customer_order,       optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  STATUSES = %w[receiving received fetching analysing needs_review already_on_file ignored error booked dismissed].freeze
  validates :status, inclusion: { in: STATUSES }
  validates :mailgun_message_id, presence: true, uniqueness: true

  scope :open,   -> { where(status: %w[receiving received fetching analysing needs_review]) }
  scope :recent, -> { order(received_at: :desc) }

  USABLE_CONTENT_TYPES = %w[application/pdf image/jpeg image/png image/webp image/gif].freeze

  def usable_attachments
    attachments.reject { |a| a["inline"] }.select { |a| USABLE_CONTENT_TYPES.include?(a["content_type"].to_s.downcase) }
  end

  def pdf_attachments
    attachments.select { |a| a["content_type"].to_s.downcase == "application/pdf" }
  end

  def image_attachments
    attachments.reject { |a| a["inline"] }.select { |a| a["content_type"].to_s.downcase.start_with?("image/") }
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
  # Book it in: CustomerOrder (or the existing one the proposal points at),
  # PO document attached, one WorksOrder per line. Called by the assistant
  # itself when the proposal is clean, or by a reviewer (console / review
  # page) for the ones that parked. Works orders then surface on the
  # Contract Review board like any other — that's the human check.
  #
  #   ipo.create_order!(reviewed_by: user)
  #
  # Overrides if the assistant misread something:
  #   ipo.create_order!(reviewed_by: u, customer_id: "…", number: "PO-1234",
  #                     lines: [{ "part_number" => "…", "part_issue" => "A", "quantity" => 5 }])
  #   ipo.create_order!(reviewed_by: u, lines: [])   # order + PO only, no works orders
  #
  # Partial bookings: the assistant books the lines it could resolve and the
  # row parks in needs_review, linked to the order, naming the lines still
  # without a part. Calling create_order! again with just those lines books
  # them onto the SAME order (no duplicate order, PO not re-attached).
  # ---------------------------------------------------------------------------
  def create_order!(reviewed_by:, customer_id: nil, number: nil, date_received: nil, attachment_index: nil, lines: nil)
    raise "Already booked as CustomerOrder #{customer_order_id}" if status == "booked"

    customer_id ||= proposal["customer_id"]
    number      ||= proposal["po_number"]
    lines         = lines.nil? ? Array(proposal["lines"]) : Array(lines)

    transaction do
      co = book_order!(reviewed_by: reviewed_by, customer_id: customer_id, number: number,
                       date_received: date_received, order_date: proposal["order_date"],
                       attachment_index: attachment_index,
                       existing_customer_order_id: proposal["existing_customer_order_id"], lines: lines)
      update!(customer_order: co, status: "booked", reviewed_by: reviewed_by, reviewed_at: Time.current,
              summary: "Booked as #{co.display_name}" + (co.works_orders.active.any? ? " — #{co.works_orders.active.map(&:display_name).join(', ')}" : " (no works orders)"))
      co
    end
  end

  # Book ONE purchase order from this email: find or create the CustomerOrder,
  # attach the PO document, book the lines, apply minimum charges, attach
  # drawings. Does NOT touch this row's status - create_order! (single PO) and
  # the intake job (one or many POs) do that, so an email carrying two POs
  # can call this twice.
  def book_order!(reviewed_by:, customer_id:, number:, lines:, date_received: nil, order_date: nil,
                  attachment_index: nil, existing_customer_order_id: nil)
    lines = Array(lines)
    raise "No customer_id — pass one explicitly" if customer_id.blank?
    raise "No PO number — pass one explicitly"   if number.blank?
    date_received ||= (Date.parse(order_date) rescue nil) if order_date.present?

    transaction do
      co   = customer_order if customer_order&.number == number # our own, from an earlier partial booking
      co ||= CustomerOrder.find_by(id: existing_customer_order_id) if existing_customer_order_id.present?
      co ||= CustomerOrder.find_by(customer_id: customer_id, number: number)

      if co.nil?
        co = CustomerOrder.create!({ customer_id: customer_id, number: number, date_received: date_received, created_by: reviewed_by }.compact)
      elsif co != customer_order && co.po_attached? && co.works_orders.active.exists?
        raise "CustomerOrder #{co.number} already has a PO and works orders — treat as amendment"
      end

      PurchaseOrderService.attach_from_inbound(customer_order: co, inbound_purchase_order: self,
                                               attachment_index: attachment_index) unless co.po_attached?

      wos = lines.any? ? PurchaseOrderService.book_lines!(customer_order: co, lines: lines) : []

      # Works orders carry the true price; the customer's minimum charges go
      # on as additional-charge top-ups (see MinimumCharges). Recomputed over
      # the whole order, so lines added to an existing order are covered too.
      minimums = wos.any? ? MinimumCharges.apply!(co) : {}

      # Drawings the email carried for a line → that line's part (created or
      # pre-existing). Best-effort: a drawing failing to attach must not undo
      # the booking.
      drawings = []
      wos.each_with_index do |wo, i|
        idx = Array(lines[i].to_h.stringify_keys["drawing_attachment_indexes"])
        next if idx.empty?
        begin
          drawings += PurchaseOrderService.attach_drawings!(part: wo.part, inbound_purchase_order: self, indexes: idx)
        rescue => e
          Rails.logger.warn "[InboundPurchaseOrder] drawing attach failed for #{wo.part.display_name}: #{e.message}"
        end
      end

      Rails.logger.info "[InboundPurchaseOrder] booked #{co.display_name}: #{wos.map(&:display_name).join(', ')}" \
                        "#{"; #{drawings.size} drawing(s)" if drawings.any?}" \
                        "#{"; MOC top-up £#{'%.2f' % minimums[:order_top_up]}" if minimums[:order_top_up]}" \
                        "#{"; WO minimums on #{minimums[:works_order_top_ups].keys.join(', ')}" if minimums[:works_order_top_ups].present?}"
      co
    end
  end

  def dismiss!(reviewed_by:, reason: nil)
    update!(status: "dismissed", reviewed_by: reviewed_by, reviewed_at: Time.current,
            summary: [summary, reason].compact.join(" — "))
  end
end
