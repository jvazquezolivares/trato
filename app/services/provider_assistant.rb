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

    # Financial queries use a two-step flow: Claude identifies the query,
    # the service computes real data, then Claude presents it conversationally.
    if financial_query?(response)
      response = handle_financial_query(response, conversation)
    else
      execute_action(response)
    end

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
    when "create_task"
      Assistants::TaskService.call(provider: @provider, action_data: action_data)
    when "initiate_social_post", "generate_caption", "approve_caption"
      Assistants::SocialMediaService.call(provider: @provider, action: action, action_data: action_data)
    end
  end

  def financial_query?(response)
    response["action"] == "financial_query"
  end

  # Two-step financial query flow:
  # 1. FinancialQueryService computes real data from the DB
  # 2. A second Claude call presents the data conversationally
  # This ensures Claude never invents financial numbers.
  def handle_financial_query(first_response, conversation)
    action_data = first_response["action_data"] || {}

    financial_data = Assistants::FinancialQueryService.call(
      provider: @provider,
      query_type: action_data["query_type"],
      date_from: action_data["date_from"],
      date_to: action_data["date_to"]
    )

    # If the service returned an error, let Claude's original message through
    return first_response if financial_data["error"]

    build_financial_response(financial_data, conversation)
  end

  # Second Claude call: takes the computed financial data and asks Claude
  # to present it in warm, conversational Mexican Spanish.
  def build_financial_response(financial_data, conversation)
    prompt_data = Assistants::ProviderPromptBuilder.call(
      provider: @provider,
      conversation: conversation
    )

    presentation_prompt = <<~PROMPT
      El proveedor hizo una consulta financiera. Aquí están los datos REALES calculados por el sistema.
      Presenta estos datos de forma conversacional, cálida y breve. NO inventes ni modifiques ningún número.
      Usa formato legible: "$1,500" para montos. Si no hay datos, dilo amablemente.

      Datos calculados:
      #{financial_data.to_json}
    PROMPT

    ClaudeService.call(
      model: :haiku,
      system_prompt: prompt_data[:system_prompt],
      user_message: presentation_prompt,
      context: prompt_data[:context]
    )
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
