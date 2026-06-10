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

    # Check if we're awaiting a financial option selection
    if conversation.stage == "awaiting_financial_selection"
      return handle_financial_selection(conversation)
    end

    response = call_claude(conversation)

    # Handle nil response from ClaudeService
    if response.nil?
      Rails.logger.error("[ProviderAssistant] Received nil response from ClaudeService")
      response = {
        "message" => "Lo siento, tuve un problema. ¿Puedes repetir eso?",
        "action" => "none",
        "action_data" => {},
        "new_stage" => nil,
        "updated_context" => {},
        "should_save_message" => false
      }
    end

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

    # Check if the query is ambiguous (no date range specified)
    # If ambiguous, send List Message for clarification
    if ambiguous_financial_query?(action_data)
      return send_financial_options_list(conversation)
    end

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

  # Checks if a financial query is ambiguous (lacks specific date range).
  # Ambiguous queries should trigger the List Message for clarification.
  def ambiguous_financial_query?(action_data)
    query_type = action_data["query_type"]
    date_from = action_data["date_from"]
    date_to = action_data["date_to"]

    # "outstanding" queries don't need dates (they show current state)
    return false if query_type == "outstanding"

    # If query_type is present but dates are missing, it's ambiguous
    query_type.present? && (date_from.blank? || date_to.blank?)
  end

  # Sends a List Message with financial options and updates conversation stage.
  # Returns a response hash that will be persisted.
  def send_financial_options_list(conversation)
    payload = WhatsApp::ListMessageBuilder.build_financial_options_list

    WhatsAppService.send_list_message(
      to: @provider.phone,
      payload: payload,
      phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
    )

    # Update conversation stage to await selection
    conversation.update!(stage: "awaiting_financial_selection")

    # Return response for persistence
    {
      "message" => "[List Message sent: Financial options]",
      "action" => "none",
      "action_data" => {},
      "new_stage" => "awaiting_financial_selection",
      "updated_context" => {},
      "should_save_message" => false
    }
  end

  # Handles the provider's selection from the financial options List Message.
  # Routes to the appropriate financial query based on selection.
  def handle_financial_selection(conversation)
    selection_id = extract_list_selection_id(@body)

    # Handle "No, gracias" option
    if selection_id == "no_thanks"
      conversation.update!(stage: "active")
      response = {
        "message" => "Perfecto, aquí estoy si necesitas algo más 😊",
        "action" => "none",
        "action_data" => {},
        "new_stage" => "active",
        "updated_context" => {},
        "should_save_message" => false
      }
      send_reply(response)
      persist(response, conversation)
      return response
    end

    # Map selection to query type and date range
    query_params = map_selection_to_query(selection_id)

    # Execute financial query
    financial_data = Assistants::FinancialQueryService.call(
      provider: @provider,
      query_type: query_params[:query_type],
      date_from: query_params[:date_from],
      date_to: query_params[:date_to]
    )

    # Reset conversation stage
    conversation.update!(stage: "active")

    # Build conversational response
    response = build_financial_response(financial_data, conversation)
    response["new_stage"] = "active"

    send_reply(response)
    persist(response, conversation)

    response
  end

  # Extracts the selection ID from a List Message response.
  # The webhook controller already extracts the ID from the interactive payload,
  # so the body parameter contains the selection ID directly.
  def extract_list_selection_id(body)
    body&.strip&.downcase
  end

  # Maps a financial option selection ID to query parameters.
  # Returns hash with query_type, date_from, and date_to.
  def map_selection_to_query(selection_id)
    today = Date.current

    case selection_id
    when "income"
      {
        query_type: "earnings",
        date_from: today.beginning_of_month.to_s,
        date_to: today.to_s
      }
    when "expenses"
      {
        query_type: "expenses",
        date_from: today.beginning_of_month.to_s,
        date_to: today.to_s
      }
    when "pending"
      {
        query_type: "outstanding",
        date_from: nil,
        date_to: nil
      }
    else
      # Default to current month summary
      {
        query_type: "summary",
        date_from: today.beginning_of_month.to_s,
        date_to: today.to_s
      }
    end
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

    WhatsAppService.send_message(
      to: @provider.phone,
      message: message,
      phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
    )
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
