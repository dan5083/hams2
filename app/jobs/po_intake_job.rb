# app/jobs/po_intake_job.rb
#
# Stage 1 of intake. Runs once per InboundPurchaseOrder:
#   1. drop obvious noise (auto-replies, no usable attachment)
#   2. read each parked PDF/image back from Cloudinary (the controller parked
#      them at inbound_purchase_orders/<id>/ — that's the durable copy that
#      #create_order! attaches later; the assistant request strips base64
#      once it finishes)
#   3. build an AiAssistantRequest (files + email context) for the system
#      user and hand off to PoIntakeAssistantJob
require "net/http"
require "uri"
require "base64"

class PoIntakeJob < ApplicationJob
  queue_as :default

  SYSTEM_USER_EMAIL = ENV.fetch("PO_INTAKE_USER_EMAIL", "orders@hardanodisingstl.com")

  def perform(inbound_id)
    ipo = InboundPurchaseOrder.find(inbound_id)
    return unless ipo.status == "received"

    if ipo.auto_reply?
      return ipo.update!(status: "ignored", summary: "Auto-reply / bounce / notification — not processed")
    end

    usable = ipo.usable_attachments.select { |a| a["secure_url"].present? }
    if usable.empty?
      return ipo.update!(status: "needs_review",
                         summary: "No PDF or image attachment — PO may be in the email body, or this isn't a PO")
    end

    ipo.update!(status: "fetching")

    files = usable.map { |att| att.merge("base64" => Base64.strict_encode64(fetch(att["secure_url"]))) }

    request = AiAssistantRequest.create!(
      user:     system_user,
      messages: [{ "role" => "user", "content" => build_content(ipo, files) }]
    )

    ipo.update!(ai_assistant_request: request, status: "analysing")
    PoIntakeAssistantJob.perform_later(request.id, ipo.id)
  rescue => e
    Rails.logger.error "[PoIntakeJob] #{inbound_id}: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    InboundPurchaseOrder.find_by(id: inbound_id)&.update!(status: "error", error: "#{e.class}: #{e.message}")
  end

  private

  def system_user
    User.find_by(email_address: SYSTEM_USER_EMAIL) or
      raise "PO intake system user #{SYSTEM_USER_EMAIL} not found — create it (see README)"
  end

  def fetch(url)
    uri = URI(url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.get(uri.request_uri) }
    raise "Cloudinary fetch failed #{res.code} for #{url}" unless res.is_a?(Net::HTTPSuccess)
    res.body
  end

  def build_content(ipo, files)
    blocks = files.map do |f|
      if f["content_type"] == "application/pdf"
        { "type" => "document", "source" => { "type" => "base64", "media_type" => "application/pdf", "data" => f["base64"] } }
      else
        { "type" => "image", "source" => { "type" => "base64", "media_type" => f["content_type"], "data" => f["base64"] } }
      end
    end

    attachment_lines = ipo.attachments.map do |a|
      usable = InboundPurchaseOrder::USABLE_CONTENT_TYPES.include?(a["content_type"].to_s.downcase)
      "  [#{a['index']}] #{a['name']} (#{a['content_type']}, #{a['size']} bytes)#{usable ? '' : ' — not supplied, unsupported type'}"
    end

    blocks << {
      "type" => "text",
      "text" => <<~TXT
        EMAIL RECEIVED AT orders@ — inbound_purchase_order_id: #{ipo.id}

        From:     #{ipo.from_header.presence || ipo.sender}
        Subject:  #{ipo.subject}
        Received: #{ipo.received_at&.strftime('%d %b %Y %H:%M')}

        Attachments (indexes match the files above, in order):
        #{attachment_lines.join("\n")}

        Body:
        #{ipo.stripped_text.presence || ipo.body_plain.to_s.first(4000)}
      TXT
    }
    blocks
  end
end
