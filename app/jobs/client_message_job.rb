# frozen_string_literal: true

# Background job for processing messages sent to the client WhatsApp number.
# Routes messages through ClientAssistantOrchestrator which handles client discovery flows,
# appointment scheduling, and provider search.
class ClientMessageJob < ApplicationJob
  queue_as :default

  # Process an incoming WhatsApp message sent to the client number
  #
  # @param from [String] The sender's phone number (E.164 format)
  # @param body [String] The message text content
  # @param media_url [String, nil] Optional URL to media attachment (image, audio, etc.)
  def perform(from, body, media_url = nil)
    # For client number messages, we need to determine if this is:
    # 1. A message with a short_uuid (client contacting specific provider)
    # 2. A message without short_uuid (new client discovery flow - C2A)

    # Extract short_uuid from message body if present
    short_uuid = extract_short_uuid(body)

    if short_uuid.present?
      # Client is contacting a specific provider via their short_uuid
      provider = Provider.find_by(short_uuid: short_uuid)

      if provider
        ClientAssistantOrchestrator.call(
          provider: provider,
          from: from,
          body: body
        )
      else
        # Invalid short_uuid - could send error message or log
        Rails.logger.warn("[ClientMessageJob] Invalid short_uuid: #{short_uuid}")
      end
    else
      # No short_uuid - this is a new client discovery flow (C2A)
      # This will trigger region-based provider discovery
      ClientAssistantOrchestrator.call_search_mode(
        from: from,
        body: body
      )
    end
  end

  private

  # Extract 8-character hexadecimal short_uuid from message body
  #
  # @param body [String] The message text
  # @return [String, nil] The extracted short_uuid or nil if not found
  def extract_short_uuid(body)
    return nil if body.blank?

    # Match 8-character hexadecimal string (provider short_uuid format)
    match = body.match(/\b[0-9a-f]{8}\b/i)
    match&.to_s&.downcase
  end
end
