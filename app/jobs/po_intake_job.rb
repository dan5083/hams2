# app/jobs/po_intake_job.rb
#
# Stage 1 of intake. Runs once per InboundPurchaseOrder:
#   1. drop obvious noise (auto-replies, no usable attachment)
#   2. pull each PDF/image from Mailgun and park it in Cloudinary under
#      inbound_purchase_orders/<id>/ — Mailgun only keeps it 3 days, and the
#      assistant request strips base64 once it finishes, so this is the
#      durable copy that #create_order! attaches later
#   3. build an AiAssistantRequest (files + email context) for the system
#      user and hand off to PoIntakeAssistantJob
require "net/http"
require "uri"
require "base64"
require "tempfile"

class PoIntakeJob < ApplicationJob
  queue_as :default

  MAX_ATTACHMENT_BYTES = 20.megabytes # Anthropic request ceiling is 32MB total
  SYSTEM_USER_EMAIL    = ENV.fetch("PO_INTAKE_USER_EMAIL", "orders@hardanodisingstl.com")

  def perform(inbound_id)
    ipo = InboundPurchaseOrder.find(inbound_id)
    return unless ipo.status == "received"

    if ipo.auto_reply?
      return ipo.update!(status: "ignored", summary: "Auto-reply / bounce / notification — not processed")
    end

    usable = ipo.usable_attachments
    if usable.empty?
      return ipo.update!(status: "needs_review",
                         summary: "No PDF or image attachment — PO may be in the email body, or this isn't a PO")
    end

    ipo.update!(status: "fetching")

    files  = usable.map { |att| fetch_and_park(ipo, att) }
    parked = files.map { |f| f.except("base64") } # base64 is only for the API request, never persisted
    ipo.update!(attachments: ipo.attachments.map { |a| parked.find { |p| p["index"] == a["index"] } || a })

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

  # Returns the attachment hash with base64 + Cloudinary fields added.
  def fetch_and_park(ipo, att)
    bytes = fetch_from_mailgun(att["mailgun_url"])
    raise "Attachment #{att['name']} is #{bytes.bytesize} bytes — over the #{MAX_ATTACHMENT_BYTES} limit" if bytes.bytesize > MAX_ATTACHMENT_BYTES

    ext = att["content_type"] == "application/pdf" ? ".pdf" : File.extname(att["name"]).presence || ".jpg"
    uploaded = Tempfile.create(["inbound_po", ext], binmode: true) do |tf|
      tf.write(bytes)
      tf.flush
      Cloudinary::Uploader.upload(
        tf.path,
        public_id:     "inbound_purchase_orders/#{ipo.id}/#{att['index']}_#{File.basename(att['name'], '.*').parameterize.presence || 'attachment'}",
        resource_type: "image", # PDFs as image-type so they can be page-transformed later (see PurchaseOrderService)
        overwrite:     true,
        unique_filename: false
      )
    end

    att.merge(
      "public_id"  => uploaded["public_id"],
      "secure_url" => uploaded["secure_url"],
      "bytes"      => uploaded["bytes"],
      "base64"     => Base64.strict_encode64(bytes) # transient — stripped before persisting
    )
  end

  def fetch_from_mailgun(url)
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req.basic_auth("api", ENV.fetch("MAILGUN_API_KEY"))
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |http| http.request(req) }
    raise "Mailgun attachment fetch failed #{res.code}: #{res.body.to_s.first(200)}" unless res.is_a?(Net::HTTPSuccess)
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
