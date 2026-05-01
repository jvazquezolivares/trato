# frozen_string_literal: true

module Assistants
  # Shared service for persisting messages and updating conversation state.
  # Used by both ClientAssistantOrchestrator and ProviderAssistant to avoid
  # duplicated persistence logic.
  #
  # Usage:
  #   Assistants::ConversationPersistenceService.call(
  #     conversation: conversation, response: claude_response,
  #     inbound_body: "Hola", media_url: nil
  #   )
  class ConversationPersistenceService
    def self.call(conversation:, response:, inbound_body:, media_url: nil)
      new(
        conversation: conversation, response: response,
        inbound_body: inbound_body, media_url: media_url
      ).persist
    end

    def initialize(conversation:, response:, inbound_body:, media_url: nil)
      @conversation = conversation
      @response = response
      @inbound_body = inbound_body
      @media_url = media_url
    end

    def persist
      persist_messages if should_save?
      update_conversation
    end

    private

    def should_save?
      @response["should_save_message"]
    end

    def persist_messages
      @conversation.messages.create!(
        direction: "inbound",
        body: @inbound_body,
        media_url: @media_url,
        intent: @response["intent"],
        processed: true
      )

      return if @response["message"].blank?

      @conversation.messages.create!(
        direction: "outbound",
        body: @response["message"],
        intent: @response["intent"],
        processed: true
      )
    end

    def update_conversation
      updates = { last_message_at: Time.current }
      updates[:stage] = @response["new_stage"] if @response["new_stage"].present?
      updates[:context] = @response["updated_context"] if @response["updated_context"].present?

      @conversation.update!(updates)
    end
  end
end
