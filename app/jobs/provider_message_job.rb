# frozen_string_literal: true

# Background job for processing messages sent to the provider WhatsApp number.
# Routes messages through ConversationHandler which determines the appropriate
# conversation flow based on sender identity (known provider, client with short_uuid, or new user).
class ProviderMessageJob < ApplicationJob
  queue_as :default

  # Process an incoming WhatsApp message sent to the provider number
  #
  # @param from [String] The sender's phone number (E.164 format)
  # @param body [String] The message text content
  # @param media_url [String, nil] Optional URL to media attachment (image, audio, etc.)
  def perform(from, body, media_url = nil)
    ConversationHandler.call(
      from: from,
      body: body,
      media_url: media_url
    )
  end
end
