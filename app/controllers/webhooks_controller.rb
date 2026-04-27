# frozen_string_literal: true

class WebhooksController < ApplicationController
  # Skip CSRF protection for Meta Cloud API webhook callbacks
  skip_before_action :verify_authenticity_token, only: :receive

  # GET /webhooks/whatsapp — Meta verification handshake
  # Compares the verify token from Meta against our stored token.
  # Returns the challenge string on match, HTTP 403 on mismatch.
  def verify
    if params["hub.verify_token"] == ENV["WHATSAPP_VERIFY_TOKEN"]
      render plain: params["hub.challenge"]
    else
      render plain: "Error", status: :forbidden
    end
  end

  # POST /webhooks/whatsapp — incoming messages from Meta Cloud API
  # Always returns HTTP 200 immediately to satisfy Meta's 5-second window.
  # Extracts message data and enqueues a background job for async processing.
  def receive
    message_data = extract_message_data
    return head :ok unless message_data[:from].present?

    ProcessWhatsappMessageJob.perform_later(
      message_data[:from],
      message_data[:body],
      message_data[:media_url]
    )

    head :ok
  end

  private

  # Extracts sender phone, text body, and image URL from the Meta webhook payload.
  # Uses dig to safely navigate the nested JSON structure.
  def extract_message_data
    entry = params.dig(:entry, 0, :changes, 0, :value)

    {
      from: entry&.dig(:messages, 0, :from),
      body: entry&.dig(:messages, 0, :text, :body),
      media_url: entry&.dig(:messages, 0, :image, :url)
    }
  end
end
