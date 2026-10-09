# app/models/ai_assistant_request.rb
#
# messages never hold file bytes: the controller replaces base64 blocks with
# "hams_file" reference blocks (see AssistantAttachments) before the row is
# created, so a request can be re-read — and its files re-used — on any
# later turn. The old strip_base64_from_messages! is gone with it.
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

  # Attachment reference blocks, in the order they were attached.
  def attachments      = AssistantAttachments.refs(messages)
  def pdf_attachments   = AssistantAttachments.pdfs(messages)
  def image_attachments = AssistantAttachments.images(messages)
end
