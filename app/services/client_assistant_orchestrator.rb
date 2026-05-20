# frozen_string_literal: true

# Orchestrates client-facing conversations (Elisa attending Mariana).
# Thin coordinator that delegates to specialized services under Assistants::
#
# Routing: ConversationHandler calls this when the message body
# matches a Provider.short_uuid, or when a client is in search mode.
class ClientAssistantOrchestrator
  def self.call(provider:, from:, body:)
    new(provider: provider, from: from, body: body).process
  end

  def self.call_search_mode(from:, body:)
    new_search_mode(from: from, body: body).process_search_mode
  end

  def self.new_search_mode(from:, body:)
    new(provider: nil, from: from, body: body)
  end

  def initialize(provider:, from:, body:)
    @provider = provider
    @from = from
    @body = body
  end

  # Process messages from client number without short_uuid (C2A Region-Based Discovery)
  # This handles the new discovery flow where clients message the client number directly
  def process_search_mode
    # Detect state from phone prefix
    detected_state = ZonesService.detect_state_from_prefix(@from)

    if detected_state.present?
      # C2A flow: Region detected, ask for confirmation
      handle_region_detected(detected_state)
    else
      # Fallback to existing search mode if no region detected
      Assistants::ProviderSearchService.call(from: @from, body: @body)
    end
  end

  def process
    client = find_or_initialize_client
    conversation = find_or_create_conversation(client)

    # Short-circuit: if the client is in a review collection flow,
    # delegate directly to ReviewCollectionService (skip Claude).
    return handle_review_collection(client, conversation) if review_collection_active?(conversation)

    # Short-circuit: if the client sends a rating (1–5) and has a
    # pending review job, start the review collection flow.
    return start_review_collection(client, conversation) if review_rating_detected?(conversation)

    handle_pre_escalation(conversation)

    response = call_claude(conversation, client)

    # Handle nil response from ClaudeService
    if response.nil?
      Rails.logger.error("[ClientAssistantOrchestrator] Received nil response from ClaudeService")
      response = {
        "message" => "Lo siento, tuve un problema. ¿Puedes repetir eso?",
        "action" => "none",
        "action_data" => {},
        "new_stage" => nil,
        "updated_context" => {},
        "should_save_message" => false
      }
    end

    execute_action(response, client, conversation)
    send_reply(response)
    persist(response, conversation)

    response
  end

  private

  def find_or_initialize_client
    return nil if @from.blank?

    client = Client.find_or_initialize_by(phone: @from)
    client.save! if client.new_record?
    client
  end

  def find_or_create_conversation(client)
    Conversation.find_or_create_by!(
      provider: @provider,
      phone: @from,
      role: "client"
    ) do |conversation|
      conversation.client = client
      conversation.stage = "active"
      conversation.context = {}
      conversation.last_message_at = Time.current
    end
  end

  # --- Pre-Claude escalation check ---

  def handle_pre_escalation(conversation)
    result = Assistants::EscalationDetector.call(
      body: @body, from: @from,
      provider: @provider, conversation: conversation
    )

    return unless result[:detected]

    Assistants::EscalationDetector.escalate!(
      conversation: conversation, provider: @provider,
      from: @from, body: @body, reason: result[:reason]
    )
  end

  # --- Claude interaction ---

  def call_claude(conversation, client)
    prompt_data = Assistants::ClientPromptBuilder.call(
      provider: @provider, client: client,
      conversation: conversation, from: @from
    )

    ClaudeService.call(
      model: :haiku,
      system_prompt: prompt_data[:system_prompt],
      user_message: @body,
      context: prompt_data[:context]
    )
  end

  # --- Review collection ---

  def review_collection_active?(conversation)
    Assistants::ReviewCollectionService.collecting_review?(conversation)
  end

  def review_rating_detected?(conversation)
    Assistants::ReviewCollectionService.review_rating?(body: @body, conversation: conversation)
  end

  def handle_review_collection(client, conversation)
    response = Assistants::ReviewCollectionService.call(
      provider: @provider, client: client,
      conversation: conversation, body: @body
    )
    send_reply(response)
    persist(response, conversation)
    response
  end

  def start_review_collection(client, conversation)
    response = Assistants::ReviewCollectionService.call(
      provider: @provider, client: client,
      conversation: conversation, body: @body
    )
    send_reply(response)
    persist(response, conversation)
    response
  end

  # --- Action dispatch ---

  def execute_action(response, client, conversation)
    action = response["action"]
    action_data = response["action_data"] || {}

    case action
    when "create_appointment"
      Assistants::AppointmentService.call(
        provider: @provider, client: client, from: @from,
        action_data: action_data, conversation: conversation
      )
    when "send_photos"
      send_work_photos(action_data)
    when "send_review_summary"
      Assistants::ReviewSummaryService.call(provider: @provider, to: @from)
    when "collect_review"
      Assistants::ReviewCollectionService.call(
        provider: @provider, client: client,
        conversation: conversation, body: @body
      )
    when "escalate"
      Assistants::EscalationDetector.escalate!(
        conversation: conversation, provider: @provider,
        from: @from, body: @body,
        reason: action_data["reason"] || "claude_detected",
        detail: action_data["detail"]
      )
    when "notify_provider"
      notify_provider(action_data)
    when "send_provider_phone"
      send_provider_phone
    end
  end

  # --- Photo sending (lightweight, stays in orchestrator) ---

  def send_work_photos(action_data)
    category = action_data["category"]

    photos = if category.present?
               @provider.photos
                        .where(profile_photo: false)
                        .where("category_tags @> ?", [ category ].to_json)
                        .limit(5)
    else
               @provider.photos
                        .where(profile_photo: false)
                        .limit(5)
    end

    return if photos.empty?

    photo_messages = photos.map do |photo|
      caption = photo.caption.present? ? "📸 #{photo.caption}" : "📸 Trabajo realizado"
      "#{caption}\n#{photo.url}"
    end

    WhatsAppService.send_multipart(to: @from, messages: photo_messages)

    profile_url = "trato.mx/p/#{@provider.slug}"
    WhatsAppService.send_message(to: @from, message: "Puedes ver más fotos y reseñas aquí: #{profile_url}")
  end

  def notify_provider(action_data)
    message = action_data["message"] || "Un cliente necesita tu atención."
    WhatsAppService.send_message(to: @provider.phone, message: message)
  end

  def send_provider_phone
    WhatsAppService.send_message(
      to: @from,
      message: "El número directo de #{@provider.name} es: #{@provider.phone}. " \
               "También puedo decirle que te llame, ¿qué prefieres?"
    )
  end

  def send_reply(response)
    message = response["message"]
    return if message.blank? || @from.blank?

    WhatsAppService.send_message(to: @from, message: message)
  end

  def persist(response, conversation)
    Assistants::ConversationPersistenceService.call(
      conversation: conversation,
      response: response,
      inbound_body: @body
    )
  end

  # --- C2A Region-Based Discovery ---

  # Handle region detection and send confirmation message
  # @param detected_state [String] The detected state name (e.g., "Veracruz")
  def handle_region_detected(detected_state)
    greeting_message = "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de #{detected_state}. " \
                       "¿Buscas un técnico en esta región?"

    # Send greeting with Quick Reply Buttons
    WhatsAppService.send_message_with_buttons(
      to: @from,
      message: greeting_message,
      buttons: [
        { id: "region_yes_#{detected_state}", title: "Sí, en #{detected_state}" },
        { id: "region_no", title: "No, en otro lugar" }
      ]
    )

    # Store detected region in conversation context (Redis for now, since no provider yet)
    store_search_context(detected_state: detected_state, stage: "region_confirmation")
  end

  # Store search context in Redis for stateless client discovery flow
  # @param context_data [Hash] Context data to store
  def store_search_context(**context_data)
    redis_key = "client_search:#{@from}"
    REDIS.setex(redis_key, 86_400, context_data.to_json) # 24 hour TTL
  end

  # Retrieve search context from Redis
  # @return [Hash, nil] The stored context data or nil if not found
  def get_search_context
    redis_key = "client_search:#{@from}"
    data = REDIS.get(redis_key)
    return nil if data.blank?

    JSON.parse(data, symbolize_names: true)
  rescue JSON::ParserError => e
    Rails.logger.error("[ClientAssistantOrchestrator] Failed to parse search context: #{e.message}")
    nil
  end
end
