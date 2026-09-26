# app/controllers/inbound/purchase_orders_controller.rb
#
# Mailgun forward() endpoint for the orders@ route.
#
#   config/routes.rb:
#     namespace :inbound do
#       post "purchase_orders", to: "purchase_orders#create"
#     end
#
#   Mailgun route: match_recipient("po@hams-2.co.uk")
#                  forward("https://hams-2.co.uk/inbound/purchase_orders")
#
# Mailgun posts the fully parsed message as multipart form data: sender,
# subject, body-plain, stripped-text, message-headers (JSON), Message-Id,
# attachment-count, and the attachments themselves as file fields
# attachment-1 .. attachment-N. timestamp/token/signature are signed with the
# HTTP webhook signing key (ENV["MAILGUN_WEBHOOK_SIGNING_KEY"]).
#
# Attachments are parked in Cloudinary here, in the request, because Mailgun
# doesn't keep them — this is the only moment we have the bytes. A couple of
# PDFs take a few seconds, well inside Heroku's 30s.
#
# Response codes matter: Mailgun retries anything non-2xx for ~8 hours,
# except 406 which it treats as "don't bother".
require "tempfile"

module Inbound
  class PurchaseOrdersController < ApplicationController
    # Adjust to whatever ApplicationController uses to skip auth —
    # `allow_unauthenticated_access` is the Rails 8 authentication generator's.
    allow_unauthenticated_access
    skip_forgery_protection

    MAX_ATTACHMENT_BYTES = 20.megabytes

    def create
      return head :not_acceptable unless valid_signature?

      message_id = params["Message-Id"].presence || header_hash["Message-Id"].presence
      return head :not_acceptable if message_id.blank?

      ipo = InboundPurchaseOrder.find_or_initialize_by(mailgun_message_id: message_id)

      # A retry after we already got everything parked: nothing to do.
      return head :ok if ipo.persisted? && ipo.status != "receiving"

      ipo.assign_attributes(
        sender:        params["sender"],
        from_header:   params["from"],
        recipient:     params["recipient"],
        subject:       params["subject"].to_s.first(500),
        body_plain:    params["body-plain"],
        stripped_text: params["stripped-text"],
        received_at:   received_at,
        headers:       header_hash,
        status:        "receiving"
      )
      ipo.save!

      # Park every attachment before flipping to "received". If Cloudinary
      # fails part-way we return 500, Mailgun retries, and the "receiving"
      # status lets the retry redo the uploads (overwrite: true).
      ipo.update!(attachments: park_attachments(ipo), status: "received")

      PoIntakeJob.perform_later(ipo.id)
      head :ok
    rescue ActiveRecord::RecordNotUnique
      head :ok
    end

    private

    def valid_signature?
      key = ENV["MAILGUN_WEBHOOK_SIGNING_KEY"]
      raise "MAILGUN_WEBHOOK_SIGNING_KEY not set" if key.blank?

      timestamp = params["timestamp"].to_s
      token     = params["token"].to_s
      signature = params["signature"].to_s
      return false if timestamp.blank? || token.blank? || signature.blank?

      expected = OpenSSL::HMAC.hexdigest("SHA256", key, timestamp + token)
      ActiveSupport::SecurityUtils.secure_compare(expected, signature)
    end

    # "message-headers" is a JSON array of [name, value] pairs.
    def header_hash
      @header_hash ||= begin
        pairs = JSON.parse(params["message-headers"].presence || "[]")
        pairs.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s.first(1000) }
      rescue JSON::ParserError
        {}
      end
    end

    # Uploaded files arrive as attachment-1 .. attachment-N.
    def uploaded_attachments
      params.to_unsafe_h
            .select { |k, v| k.to_s.match?(/\Aattachment-\d+\z/) && v.respond_to?(:tempfile) }
            .sort_by { |k, _| k.to_s[/\d+/].to_i }
            .map(&:last)
    end

    # Every attachment gets a record; only PDFs/images get parked in
    # Cloudinary (the job decides what's usable, the reviewer can see the rest
    # was there).
    def park_attachments(ipo)
      uploaded_attachments.each_with_index.map do |file, i|
        content_type = file.content_type.to_s.downcase
        att = {
          "index"        => i,
          "name"         => file.original_filename.to_s,
          "content_type" => content_type,
          "size"         => file.size.to_i
        }

        next att unless InboundPurchaseOrder::USABLE_CONTENT_TYPES.include?(content_type)
        next att.merge("skipped" => "over #{MAX_ATTACHMENT_BYTES} bytes") if file.size.to_i > MAX_ATTACHMENT_BYTES

        uploaded = Cloudinary::Uploader.upload(
          file.tempfile.path,
          public_id:       "inbound_purchase_orders/#{ipo.id}/#{i}_#{File.basename(att['name'], '.*').parameterize.presence || 'attachment'}",
          resource_type:   "image", # PDFs as image-type so they can be page-transformed later (see PurchaseOrderService)
          overwrite:       true,
          unique_filename: false
        )

        att.merge("public_id" => uploaded["public_id"], "secure_url" => uploaded["secure_url"], "bytes" => uploaded["bytes"])
      end
    end

    def received_at
      ts = params["timestamp"].to_i
      ts.positive? ? Time.at(ts).utc : Time.current
    end
  end
end
