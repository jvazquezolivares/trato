# frozen_string_literal: true

# Handles all provider-facing conversations (Elisa attending Miguel).
# Delegates to Assistants:: services for prompt building and persistence.
#
# Routing: ConversationHandler calls this when the sender's phone
# matches a Provider.phone record.
class ProviderAssistant
  def self.call(provider:, body:, media_url: nil)
    new(provider: provider, body: body, media_url: media_url).process
  end

  def initialize(provider:, body:, media_url: nil)
    @provider = provider
    @body = body
    @media_url = media_url
  end

  def process
    conversation = find_or_create_conversation
    response = call_claude(conversation)

    execute_action(response)
    send_reply(response)
    persist(response, conversation)

    response
  end

  private

  def find_or_create_conversation
    Conversation.find_or_create_by!(
      phone: @provider.phone,
      provider: @provider,
      role: "provider"
    ) do |conversation|
      conversation.stage = "active"
      conversation.context = {}
      conversation.last_message_at = Time.current
    end
  end

  def call_claude(conversation)
    prompt_data = Assistants::ProviderPromptBuilder.call(
      provider: @provider,
      conversation: conversation
    )

    ClaudeService.call(
      model: :haiku,
      system_prompt: prompt_data[:system_prompt],
      user_message: @body,
      context: prompt_data[:context]
    )
  end

  def execute_action(response)
    action = response["action"]
    action_data = response["action_data"] || {}

    case action
    when "register_job"
      JobRegistrationService.call(provider: @provider, action: "register_job", action_data: action_data)
    when "register_expense"
      JobRegistrationService.call(provider: @provider, action: "register_expense", action_data: action_data)
    when "update_work_day"
      Assistants::WorkDayService.call(provider: @provider, action_data: action_data)
    end
  end

  def send_reply(response)
    message = response["message"]
    return if message.blank?

    WhatsAppService.send_message(to: @provider.phone, message: message)
  end

  def persist(response, conversation)
    Assistants::ConversationPersistenceService.call(
      conversation: conversation,
      response: response,
      inbound_body: @body,
      media_url: @media_url
    )
  end
end
