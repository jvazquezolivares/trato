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
    puts "[DEBUG WebhooksController] ===== WEBHOOK RECEIVED ====="
    puts "[DEBUG WebhooksController] Params: #{params.to_unsafe_h.inspect}"

    phone_number_id = extract_phone_number_id
    message_data = extract_message_data

    puts "[DEBUG WebhooksController] phone_number_id: #{phone_number_id}"
    puts "[DEBUG WebhooksController] message_data: #{message_data.inspect}"

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
  # For interactive messages (List Message selections), extracts the selected option ID.
  def extract_message_data
    entry = params.dig(:entry, 0, :changes, 0, :value)
    message = entry&.dig(:messages, 0)

    # Check if this is an interactive message response (List Message selection)
    if message&.dig(:type) == "interactive"
      interactive_type = message.dig(:interactive, :type)

      # Extract selection ID based on interactive type
      body = case interactive_type
             when "list_reply"
               message.dig(:interactive, :list_reply, :id)
             when "button_reply"
               message.dig(:interactive, :button_reply, :id)
             else
               nil
             end
    else
      # Regular text message
      body = message&.dig(:text, :body)
    end

    {
      from: message&.dig(:from),
      body: body,
      media_url: message&.dig(:image, :url)
    }
  end
end
