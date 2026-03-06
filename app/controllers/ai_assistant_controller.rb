# app/controllers/ai_assistant_controller.rb
require "net/http"
require "uri"
require "json"

class AiAssistantController < ApplicationController
  before_action :require_authentication
  before_action :require_ai_access

  # POST /ai_assistant/chat
  # Enqueues the job and immediately returns a request_id for polling.
  def chat
    messages = params[:messages]

    unless messages.is_a?(Array) && messages.any?
      render json: { error: "No messages provided" }, status: :bad_request
      return
    end

    request = AiAssistantRequest.create!(
      user:     Current.user,
      messages: messages
    )

    AiAssistantJob.perform_later(request.id)

    render json: { request_id: request.id }
  end

  # GET /ai_assistant/status/:id
  # Polled by the frontend every 2 seconds until status is complete or error.
  def status
    request = AiAssistantRequest.find_by(id: params[:id], user: Current.user)

    unless request
      render json: { error: "Not found" }, status: :not_found
      return
    end

    render json: {
      status:   request.status,
      response: request.response,
      error:    request.error
    }
  end

  private

  def require_ai_access
    render json: { error: "Access denied." }, status: :forbidden unless Current.user&.can_use_ai_assistant?
  end
end
