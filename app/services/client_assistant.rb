# frozen_string_literal: true

# Handles all client-facing conversations (Mariana's assistant).
# Manages appointment scheduling, photo sharing, review collection, and escalation.
# Stub — full implementation in task 12.
class ClientAssistant
  def self.call(provider:, from:, body:)
    Rails.logger.info("[ClientAssistant] Stub called for provider #{provider&.short_uuid}")
    nil
  end

  # Search mode: client is looking for a provider by name/category.
  # Triggered when unknown sender responds "1" to the welcome message.
  def self.call_search_mode(from:, body:)
    Rails.logger.info("[ClientAssistant] Stub search mode called from #{from}")
    nil
  end
end
