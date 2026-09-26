# app/controllers/inbound/purchase_orders_controller.rb
#
# Mailgun store-and-notify endpoint for the orders@ route.
#
#   config/routes.rb:
#     namespace :inbound do
#       post "purchase_orders", to: "purchase_orders#create"
#     end
#
#   Mailgun route: match_recipient("po@hams-2.co.uk")
#                  store(notify="https://hams-2.co.uk/inbound/purchase_orders")
#
# Mailgun posts form-encoded fields (sender, subject, body-plain, ...) plus
# timestamp/token/signature signed with the HTTP webhook signing key
# (ENV["MAILGUN_WEBHOOK_SIGNING_KEY"]). Attachments arrive as a JSON array of
# API URLs, fetched later by PoIntakeJob.
#
# Response codes matter: Mailgun retries anything non-2xx for ~8 hours,
# except 406 which it treats as "don't bother".
module Inbound
  class PurchaseOrdersController < ApplicationController
    # Adjust to whatever ApplicationController uses to skip auth —
    # `allow_unauthenticated_access` is the Rails 8 authentication generator's.
    allow_unauthenticated_access
    skip_forgery_protection

    def create
      return head :not_acceptable unless valid_signature?

      message_id = params["Message-Id"].presence || header_hash["Message-Id"].presence
      return head :not_acceptable if message_id.blank?

      ipo = InboundPurchaseOrder.find_by(mailgun_message_id: message_id)
      return head :ok if ipo # Mailgun retry or duplicate delivery — already have it

      ipo = InboundPurchaseOrder.create!(
        mailgun_message_id: message_id,
        message_url:        params["message-url"],
        sender:             params["sender"],
        from_header:        params["from"],
        recipient:          params["recipient"],
        subject:            params["subject"].to_s.first(500),
        body_plain:         params["body-plain"],
        stripped_text:      params["stripped-text"],
        received_at:        received_at,
        headers:            header_hash,
        attachments:        attachment_list
      )

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

    # [{ "url", "content-type", "name", "size" }, ...]
    def attachment_list
      list = JSON.parse(params["attachments"].presence || "[]")
      list.each_with_index.map do |a, i|
        {
          "index"        => i,
          "name"         => a["name"].to_s,
          "content_type" => a["content-type"].to_s,
          "size"         => a["size"].to_i,
          "mailgun_url"  => a["url"].to_s
        }
      end
    rescue JSON::ParserError
      []
    end

    def received_at
      ts = params["timestamp"].to_i
      ts.positive? ? Time.at(ts).utc : Time.current
    end
  end
end
