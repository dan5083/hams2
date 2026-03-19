# app/models/ai_assistant_request.rb
class AiAssistantRequest < ApplicationRecord
  belongs_to :user

  scope :recent, -> { where("created_at > ?", 24.hours.ago) }

  def pending?  = status == "pending"
  def complete? = status == "complete"
  def error?    = status == "error"

  def mark_complete!(response_text)
    update!(status: "complete", response: response_text)
    strip_base64_from_messages!
  end

  def mark_error!(message)
    update!(status: "error", error: message)
    strip_base64_from_messages!
  end

  private

  def strip_base64_from_messages!
    return unless messages.is_a?(Array)

    cleaned = messages.map do |m|
      content = m["content"]
      next m unless content.is_a?(Array)

      m.merge("content" => content.map { |c|
        if c.dig("source", "type") == "base64"
          c.merge("source" => { "type" => "stripped", "media_type" => c.dig("source", "media_type") })
        else
          c
        end
      })
    end

    update_columns(messages: cleaned.to_json)
  end
end
