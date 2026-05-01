# frozen_string_literal: true

# Thin delegator to ClientAssistantOrchestrator.
# Preserves the public interface used by ConversationHandler.
class ClientAssistant
  def self.call(provider:, from:, body:)
    ClientAssistantOrchestrator.call(provider: provider, from: from, body: body)
  end

  def self.call_search_mode(from:, body:)
    ClientAssistantOrchestrator.call_search_mode(from: from, body: body)
  end
end
