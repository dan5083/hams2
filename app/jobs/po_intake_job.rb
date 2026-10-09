# app/jobs/po_intake_job.rb
#
# Stage 1 of intake. Runs once per InboundPurchaseOrder:
#   1. drop obvious noise (auto-replies, no usable attachment)
#   2. upload each parked PDF/image to the Anthropic Files API, once, so
#      every turn of the assistant run references it by id instead of
#      carrying the bytes (the controller parked them in Cloudinary at
#      inbound_purchase_orders/<id>/ — that's the durable copy that
#      #create_order! attaches later)
#   3. build an AiAssistantRequest (file references + email context) for the
#      system user and hand off to PoIntakeAssistantJob

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

    files = usable.map { |att| file_ref(att) }
    # Remember the file_ids on the row so a retry doesn't upload twice.
    ids   = files.to_h { |f| [f["index"], f["file_id"]] }
    ipo.update!(attachments: ipo.attachments.map { |a| ids[a["index"]] ? a.merge("file_id" => ids[a["index"]]) : a })

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

  # Parked attachment -> "hams_file" reference block (AssistantAttachments
  # shape). A Mailgun retry re-runs this job, so reuse a file_id already on
  # the attachment rather than uploading again.
  def file_ref(att)
    file_id = att["file_id"].presence ||
              AnthropicFiles.upload_from_url(att["secure_url"], filename: att["name"], media_type: att["content_type"]) ||
              raise("could not upload #{att['name']} to Anthropic Files")

    { "type" => AssistantAttachments::TYPE, "file_id" => file_id,
      "public_id" => att["public_id"], "secure_url" => att["secure_url"],
      "content_type" => att["content_type"], "name" => att["name"], "bytes" => att["bytes"],
      "index" => att["index"] }
  end

  def build_content(ipo, files)
    blocks = files.map { |f| f.except("index") }

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
