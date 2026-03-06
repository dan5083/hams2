# app/models/ai_assistant_request.rb
class AiAssistantRequest < ApplicationRecord
  belongs_to :user

  scope :recent, -> { where("created_at > ?", 24.hours.ago) }

  def pending?  = status == "pending"
  def complete? = status == "complete"
  def error?    = status == "error"

  def mark_complete!(response_text)
    update!(status: "complete", response: response_text)
  end

  def mark_error!(message)
    update!(status: "error", error: message)
  end
end
