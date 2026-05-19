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
  # Extracts message data and routes to appropriate job based on phone_number_id.
  def receive
    phone_number_id = extract_phone_number_id
    message_data = extract_message_data
    return head :ok unless message_data[:from].present?

    route_message(
      phone_number_id,
      message_data[:from],
      message_data[:body],
      message_data[:media_url]
    )

    head :ok
  end

  private

  # Routes incoming messages to the appropriate job based on phone_number_id.
  # Provider messages go to ProviderMessageJob, client messages to ClientMessageJob.
  # Unknown phone_number_id values are logged as warnings.
  def route_message(phone_number_id, from, body, media_url)
    case phone_number_id
    when ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
      ProviderMessageJob.perform_later(from, body, media_url)
    when ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
      ClientMessageJob.perform_later(from, body, media_url)
    else
      Rails.logger.warn(
        "[WebhooksController] Unknown phone_number_id received: #{phone_number_id} | " \
        "Sender: #{from} | " \
        "Message preview: #{body&.truncate(50)} | " \
        "Timestamp: #{Time.current}"
      )
    end
  end

  # Extracts the phone_number_id from the Meta webhook payload.
  # This identifier determines which WhatsApp Business number received the message.
  # Returns nil if the phone_number_id is not present in the payload.
  def extract_phone_number_id
    params.dig(:entry, 0, :changes, 0, :value, :metadata, :phone_number_id)
  end

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
