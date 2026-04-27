# frozen_string_literal: true

# Processes incoming WhatsApp messages asynchronously so the webhook
# can return HTTP 200 within Meta's 5-second window.
class ProcessWhatsappMessageJob < ApplicationJob
  queue_as :default

  def perform(from, body, media_url)
    ConversationHandler.call(from: from, body: body, media_url: media_url)
  end
end
