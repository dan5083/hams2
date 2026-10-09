# app/services/assistant_attachments.rb
#
# Attachments on an AiAssistantRequest are never stored as base64. The chat
# widget still posts them that way (and re-posts the whole history on every
# turn), so the controller runs the incoming messages through .normalise,
# which replaces every base64 block with a small reference block:
#
#   { "type"         => "hams_file",
#     "file_id"      => "file_011…",                      # Anthropic Files API
#     "public_id"    => "ai_assistant/42/9f3c…",           # Cloudinary (durable copy)
#     "secure_url"   => "https://res.cloudinary.com/…",
#     "content_type" => "image/jpeg",
#     "name"         => "IMG_4412.jpg",
#     "bytes"        => 1834211 }
#
# AiAssistantJob turns these into Files API blocks on the way to the model;
# PurchaseOrderService / ScannedDocumentService read the Cloudinary side.
# Because the history is re-posted, uploads are de-duplicated by content
# hash through Rails.cache — the same photo is uploaded once, not once per
# turn. Key names match InboundPurchaseOrder#attachments so the adopt_*
# helpers in PurchaseOrderService work on both.
require "digest"
require "base64"

module AssistantAttachments
  CACHE_TTL   = 7.days
  TYPE        = "hams_file".freeze
  MAX_BYTES   = 20.megabytes

  # messages (Array of Hash, string keys) -> same shape, base64 replaced.
  def self.normalise(messages, owner:)
    Array(messages).map do |msg|
      content = msg["content"]
      next msg unless content.is_a?(Array)
      msg.merge("content" => content.map { |block| normalise_block(block, owner: owner) })
    end
  end

  # Every reference block in a request, in message order.
  def self.refs(messages)
    Array(messages).flat_map do |msg|
      content = msg["content"]
      content.is_a?(Array) ? content.select { |b| b["type"] == TYPE } : []
    end
  end

  def self.pdfs(messages)   = refs(messages).select { |r| r["content_type"] == "application/pdf" }
  def self.images(messages) = refs(messages).select { |r| r["content_type"].to_s.start_with?("image/") }

  # ---------------------------------------------------------------------------

  def self.normalise_block(block, owner:)
    source = block["source"]
    return block unless source.is_a?(Hash) && source["type"] == "base64" && source["data"].present?

    media_type = source["media_type"].to_s.downcase
    data       = source["data"]
    sha        = Digest::SHA256.hexdigest(data)

    ref = Rails.cache.fetch("assistant_attachment:#{sha}", expires_in: CACHE_TTL) do
      upload(Base64.decode64(data), media_type: media_type, name: block["title"], owner: owner, sha: sha)
    end
    ref
  end
  private_class_method :normalise_block

  def self.upload(bytes, media_type:, name:, owner:, sha:)
    raise "Attachment over #{MAX_BYTES} bytes" if bytes.bytesize > MAX_BYTES

    ext      = media_type == "application/pdf" ? "pdf" : media_type.split("/").last.to_s.sub("jpeg", "jpg")
    filename = name.presence || "#{sha[0, 12]}.#{ext}"

    cloud = Tempfile.create(["assistant", ".#{ext}"], binmode: true) do |tmp|
      tmp.write(bytes)
      tmp.flush
      Cloudinary::Uploader.upload(
        tmp.path,
        public_id:       "ai_assistant/#{owner.id}/#{sha[0, 16]}",
        resource_type:   "image", # PDFs as image-type so they can be page-transformed (see PurchaseOrderService)
        overwrite:       true,
        unique_filename: false
      )
    end

    file_id = AnthropicFiles.upload(bytes, filename: filename, media_type: media_type)

    {
      "type"         => TYPE,
      "file_id"      => file_id,
      "public_id"    => cloud["public_id"],
      "secure_url"   => cloud["secure_url"],
      "content_type" => media_type,
      "name"         => filename,
      "bytes"        => bytes.bytesize
    }
  end
  private_class_method :upload
end
