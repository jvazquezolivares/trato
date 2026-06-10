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
    # Check if we have an ongoing search context
    search_context = get_search_context

    if search_context.present?
      # Handle response based on current stage
      handle_search_flow_response(search_context)
    else
      # New conversation - detect state from phone prefix
      detected_state = ZonesService.detect_state_from_prefix(@from)

      if detected_state.present?
        # C2A flow: Region detected, ask for confirmation
        handle_region_detected(detected_state)
      else
        # Fallback to existing search mode if no region detected
        Assistants::ProviderSearchService.call(from: @from, body: @body)
      end
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

    send_client_multipart(to: @from, messages: photo_messages)

    profile_url = "trato.mx/p/#{@provider.slug}"
    send_client_message(to: @from, message: "Puedes ver más fotos y reseñas aquí: #{profile_url}")
  end

  def notify_provider(action_data)
    message = action_data["message"] || "Un cliente necesita tu atención."
    send_provider_message(to: @provider.phone, message: message)
  end

  def send_provider_phone
    send_client_message(
      to: @from,
      message: "El número directo de #{@provider.name} es: #{@provider.phone}. " \
               "También puedo decirle que te llame, ¿qué prefieres?"
    )
  end

  def send_reply(response)
    message = response["message"]
    return if message.blank? || @from.blank?

    send_client_message(to: @from,
      message: message,
      phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
    )
  end

  def persist(response, conversation)
    Assistants::ConversationPersistenceService.call(
      conversation: conversation,
      response: response,
      inbound_body: @body
    )
  end

  # Helper method to send messages to clients using the client phone number ID
  def send_client_message(to:, message:)
    WhatsAppService.send_message(
      to: to,
      message: message,
      phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
    )
  end

  def send_client_list_message(to:, payload:)
    WhatsAppService.send_list_message(
      to: to,
      payload: payload,
      phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
    )
  end

  def send_client_message_with_buttons(to:, message:, buttons:)
    WhatsAppService.send_message_with_buttons(
      to: to,
      message: message,
      buttons: buttons,
      phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
    )
  end

  def send_client_multipart(to:, messages:)
    WhatsAppService.send_multipart(
      to: to,
      messages: messages,
      phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
    )
  end

  # Helper method to send messages to providers using the provider phone number ID
  def send_provider_message(to:, message:)
    WhatsAppService.send_message(
      to: to,
      message: message,
      phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
    )
  end

  # --- C2A Region-Based Discovery ---

  # Handle ongoing search flow based on stored context
  # @param search_context [Hash] The stored search context with stage and data
  def handle_search_flow_response(search_context)
    stage = search_context[:stage]

    case stage
    when "region_confirmation"
      handle_region_confirmation_response(search_context)
    when "zone_selection"
      handle_zone_selection_response(search_context)
    when "category_selection"
      handle_category_selection_response(search_context)
    when "provider_selection"
      handle_provider_selection_response(search_context)
    when "slot_selection"
      handle_slot_selection_response(search_context)
    when "appointment_confirmation"
      handle_appointment_confirmation_response(search_context)
    when "appointment_escalation"
      handle_appointment_escalation_response(search_context)
    else
      Rails.logger.warn("[ClientAssistantOrchestrator] Unknown search stage: #{stage}")
      # Fallback to new search
      detected_state = ZonesService.detect_state_from_prefix(@from)
      handle_region_detected(detected_state) if detected_state.present?
    end
  end

  # Handle response to region confirmation question
  # @param search_context [Hash] The stored search context with detected_state
  def handle_region_confirmation_response(search_context)
    detected_state = search_context[:detected_state]

    # Check if user confirmed the detected region
    # Button IDs: "region_yes_#{state}" or "region_no"
    # Also accept natural language responses like "Sí", "Si", "Yes", etc.
    if region_confirmed?(@body, detected_state)
      # User confirmed - show zones for detected state
      zones = ZonesService.zones_for_state(detected_state)

      if zones.empty?
        # No zones found for this state (shouldn't happen with valid config)
        Rails.logger.error("[ClientAssistantOrchestrator] No zones found for state: #{detected_state}")
        send_client_message(to: @from,
          message: "Lo siento, no tengo zonas configuradas para #{detected_state}. " \
                   "¿Puedes decirme en qué ciudad específica necesitas el servicio?"
        )
        return
      end

      # Send List Message with zones for this state
      zones_payload = WhatsApp::ListMessageBuilder.build_zones_list(
        zones,
        title: "Zonas en #{detected_state}"
      )

      send_client_list_message(
        to: @from,
        payload: zones_payload
      )

      # Update context to zone selection stage
      store_search_context(
        detected_state: detected_state,
        stage: "zone_selection",
        region_scope: "state" # User selected state-specific zones
      )
    elsif region_declined?(@body)
      # User declined - show all zones from all states
      zones = ZonesService.all_zones

      if zones.empty?
        Rails.logger.error("[ClientAssistantOrchestrator] No zones found in zones.json")
        send_client_message(to: @from,
          message: "Lo siento, tengo un problema técnico. ¿Puedes intentar más tarde?"
        )
        return
      end

      # Send List Message with all zones
      zones_payload = WhatsApp::ListMessageBuilder.build_zones_list(
        zones,
        title: "Todas las zonas"
      )

      send_client_list_message(
        to: @from,
        payload: zones_payload
      )

      # Update context to zone selection stage
      store_search_context(
        detected_state: detected_state,
        stage: "zone_selection",
        region_scope: "all" # User selected all zones
      )
    else
      # Unclear response - ask again
      send_client_message(to: @from,
        message: I18n.t('elisa.client.region_detection.retry_prompt', state: detected_state)
      )

      # Resend buttons
      send_client_message_with_buttons(
        to: @from,
        message: "Por favor selecciona una opción:",
        buttons: [
          { id: "region_yes_#{detected_state}", title: "Sí, en #{detected_state}" },
          { id: "region_no", title: "No, en otro lugar" }
        ]
      )
    end
  end

  # Check if user confirmed the detected region
  # @param body [String] User's message
  # @param state [String] The detected state name
  # @return [Boolean] True if user confirmed
  def region_confirmed?(body, state)
    return false if body.blank?

    normalized_body = body.downcase.strip

    # Check for button ID match
    return true if normalized_body.include?("region_yes_")

    # Check for natural language confirmation
    # Accept: "sí", "si", "yes", "sí en [state]", etc.
    confirmation_patterns = [
      /\b(sí|si|yes|ok|dale|claro|exacto)\b/i,
      /\ben #{Regexp.escape(state.downcase)}\b/i
    ]

    confirmation_patterns.any? { |pattern| normalized_body.match?(pattern) }
  end

  # Check if user declined the detected region
  # @param body [String] User's message
  # @return [Boolean] True if user declined
  def region_declined?(body)
    return false if body.blank?

    normalized_body = body.downcase.strip

    # Check for button ID match
    return true if normalized_body.include?("region_no")

    # Check for natural language decline
    # Accept: "no", "otro lugar", "otra región", etc.
    decline_patterns = [
      /\b(no|nop|nope)\b/i,
      /\botr[oa]\s+(lugar|ciudad|estado|regi[oó]n)\b/i,
      /\ben\s+otro\b/i
    ]

    decline_patterns.any? { |pattern| normalized_body.match?(pattern) }
  end

  # Handle zone selection response
  # @param search_context [Hash] The stored search context with detected_state and region_scope
  def handle_zone_selection_response(search_context)
    # The user's message should contain the selected zone
    # WhatsApp List Messages send the row ID as the message body
    selected_zone = @body.strip

    if selected_zone.blank?
      send_client_message(to: @from,
        message: "No pude identificar la zona. ¿Puedes seleccionar una opción de la lista?"
      )
      return
    end

    # Store the selected zone in context
    store_search_context(
      detected_state: search_context[:detected_state],
      region_scope: search_context[:region_scope],
      selected_zone: selected_zone,
      stage: "category_selection",
      category_page: 1 # Start with page 1
    )

    # Send categories List Message (page 1)
    categories_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

    send_client_list_message(
      to: @from,
      payload: categories_payload
    )

    Rails.logger.info("[ClientAssistantOrchestrator] Zone selected: #{selected_zone} for client #{@from}. Sent categories page 1.")
  end

  # Handle category selection response
  # @param search_context [Hash] The stored search context with selected_zone and category_page
  def handle_category_selection_response(search_context)
    # The user's message should contain the selected category ID or "Ver más categorías"
    # WhatsApp List Messages send the row ID as the message body
    selected_option = @body.strip

    if selected_option.blank?
      send_client_message(to: @from,
        message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
      )
      return
    end

    # Check if user selected "Ver más categorías"
    if selected_option == "ver_mas_categorias"
      # Send page 2 of categories
      categories_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

      send_client_list_message(
        to: @from,
        payload: categories_payload
      )

      # Update context to indicate we're on page 2
      store_search_context(
        detected_state: search_context[:detected_state],
        region_scope: search_context[:region_scope],
        selected_zone: search_context[:selected_zone],
        stage: "category_selection",
        category_page: 2
      )

      Rails.logger.info("[ClientAssistantOrchestrator] Sent categories page 2 for client #{@from}")
      return
    end

    # User selected a category - proceed to provider query (Task 17)
    selected_zone = search_context[:selected_zone]
    selected_category = selected_option

    # Query providers matching zone and category
    providers = query_providers(zone: selected_zone, category: selected_category)

    if providers.empty?
      # No providers found - trigger C2F flow (waiting for technician)
      send_client_message(to: @from,
        message: "Lo siento, aún no tenemos técnicos de #{selected_category} en #{selected_zone}. " \
                 "¿Quieres que te avisemos cuando tengamos uno disponible?"
      )

      # Task 24.2: Create or find Client record for unavailable area tracking
      client = Client.find_or_create_by!(phone: @from)

      # Task 24.4: Send Telegram notification for unavailable area
      # Get category name from ZonesService for display
      category_data = ZonesService.all_categories.find { |cat| cat["id"] == selected_category }
      category_name = category_data ? category_data["name"] : selected_category

      # Task 24.5: Telegram notification failure doesn't block main flow
      # TelegramNotifier handles all errors internally and returns nil on failure
      TelegramNotifier.notify_unavailable_area(
        client: client,
        category: category_name,
        city: selected_zone
      )

      Rails.logger.info("[ClientAssistantOrchestrator] No providers found for #{selected_category} in #{selected_zone}. Client record created/found: #{client.id}. Telegram notification attempted.")
      return
    end

    # Send provider results (page 1)
    send_provider_results(
      providers: providers,
      page: 1,
      zone: selected_zone,
      category: selected_category
    )

    # Store selected category and provider query context
    store_search_context(
      detected_state: search_context[:detected_state],
      region_scope: search_context[:region_scope],
      selected_zone: selected_zone,
      selected_category: selected_category,
      stage: "provider_selection",
      provider_page: 1
    )

    Rails.logger.info("[ClientAssistantOrchestrator] Category selected: #{selected_category} for client #{@from}. Found #{providers.count} providers.")
  end

  # Handle provider selection response
  # @param search_context [Hash] The stored search context with selected_zone, selected_category, and provider_page
  def handle_provider_selection_response(search_context)
    # The user's message should contain the selected provider ID or "Ver más" option
    # WhatsApp List Messages send the row ID as the message body
    selected_option = @body.strip

    if selected_option.blank?
      send_client_message(to: @from,
        message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
      )
      return
    end

    # Check if user selected "Ver más técnicos"
    if selected_option.start_with?("ver_mas_providers_page_")
      # Extract page number from the option ID
      page_number = selected_option.split("_").last.to_i

      # Query providers again
      providers = query_providers(
        zone: search_context[:selected_zone],
        category: search_context[:selected_category]
      )

      # Send provider results for the requested page
      send_provider_results(
        providers: providers,
        page: page_number,
        zone: search_context[:selected_zone],
        category: search_context[:selected_category]
      )

      # Update context with new page number
      store_search_context(
        detected_state: search_context[:detected_state],
        region_scope: search_context[:region_scope],
        selected_zone: search_context[:selected_zone],
        selected_category: search_context[:selected_category],
        stage: "provider_selection",
        provider_page: page_number
      )

      Rails.logger.info("[ClientAssistantOrchestrator] Sent provider results page #{page_number} for client #{@from}")
      return
    end

    # User selected a provider - extract provider ID
    if selected_option.start_with?("provider_")
      provider_id = selected_option.split("_").last.to_i
      provider = Provider.find_by(id: provider_id)

      if provider.nil?
        send_client_message(to: @from,
          message: "Lo siento, no pude encontrar ese técnico. ¿Puedes seleccionar otro?"
        )
        return
      end

      # Transition to C1A appointment scheduling flow
      transition_to_appointment_flow(provider, search_context)

      Rails.logger.info("[ClientAssistantOrchestrator] Provider selected: #{provider.name} (ID: #{provider.id}) for client #{@from}. Transitioning to appointment flow.")
    else
      send_client_message(to: @from,
        message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
      )
    end
  end

  # Handle response to appointment escalation question
  # This handles "Sí, avísale" and "No, gracias" responses when provider has no WorkDay
  # or when all slots are fully booked
  # @param search_context [Hash] The stored search context with provider_id and escalation_reason
  def handle_appointment_escalation_response(search_context)
    provider_id = search_context[:provider_id]
    provider_name = search_context[:provider_name]
    escalation_reason = search_context[:escalation_reason]

    # Find the provider
    provider = Provider.find_by(id: provider_id)

    if provider.nil?
      Rails.logger.error("[ClientAssistantOrchestrator] Provider not found: #{provider_id}")
      send_client_message(to: @from,
        message: "Lo siento, hubo un problema. ¿Puedes intentar de nuevo?"
      )
      clear_search_context
      return
    end

    # Check if user confirmed escalation
    # Button IDs: "escalate_yes" or "escalate_no"
    # Also accept natural language responses like "Sí", "Si", "Yes", etc.
    if escalation_confirmed?(@body)
      # User confirmed - notify provider and set stage to escalated
      handle_escalation_confirmed(provider, escalation_reason)
    elsif escalation_declined?(@body)
      # User declined - send closing message
      handle_escalation_declined(provider_name)
    else
      # Unclear response - ask again
      send_client_message(to: @from,
        message: "No entendí tu respuesta. ¿Quieres que le avise a #{provider_name}?"
      )

      # Resend buttons
      send_client_message_with_buttons(
        to: @from,
        message: "Por favor selecciona una opción:",
        buttons: [
          { id: "escalate_yes", title: "Sí, avísale" },
          { id: "escalate_no", title: "No, gracias" }
        ]
      )
    end
  end

  # Check if user confirmed escalation
  # @param body [String] User's message
  # @return [Boolean] True if user confirmed
  def escalation_confirmed?(body)
    return false if body.blank?

    normalized_body = body.downcase.strip

    # Check for button ID match
    return true if normalized_body.include?("escalate_yes")

    # Check for natural language confirmation
    # Accept: "sí", "si", "yes", "ok", "dale", "claro", "avísale", etc.
    confirmation_patterns = [
      /\b(sí|si|yes|ok|dale|claro|exacto|avísale|avisale)\b/i
    ]

    confirmation_patterns.any? { |pattern| normalized_body.match?(pattern) }
  end

  # Check if user declined escalation
  # @param body [String] User's message
  # @return [Boolean] True if user declined
  def escalation_declined?(body)
    return false if body.blank?

    normalized_body = body.downcase.strip

    # Check for button ID match
    return true if normalized_body.include?("escalate_no")

    # Check for natural language decline
    # Accept: "no", "no gracias", "nop", "nope", etc.
    decline_patterns = [
      /\b(no|nop|nope)\b/i,
      /\bno\s+gracias\b/i
    ]

    decline_patterns.any? { |pattern| normalized_body.match?(pattern) }
  end

  # Handle confirmed escalation - notify provider and set conversation stage to escalated
  # @param provider [Provider] The provider to notify
  # @param escalation_reason [String] The reason for escalation ("no_work_day" or "fully_booked")
  def handle_escalation_confirmed(provider, escalation_reason)
    # Find or create client record
    client = Client.find_or_initialize_by(phone: @from)
    if client.new_record?
      client.save!
      Rails.logger.info("[ClientAssistantOrchestrator] Created new client record for #{@from}")
    end

    # Find or create conversation record
    conversation = Conversation.find_or_create_by!(
      provider: provider,
      phone: @from,
      role: "client"
    ) do |conv|
      conv.client = client
      conv.stage = "escalated"
      conv.context = {
        escalation_reason: escalation_reason,
        escalated_at: Time.current.iso8601
      }
      conv.last_message_at = Time.current
    end

    # Always update conversation to set stage to escalated
    conversation.update!(
      stage: "escalated",
      context: conversation.context.merge(
        escalation_reason: escalation_reason,
        escalated_at: Time.current.iso8601
      ),
      last_message_at: Time.current
    )

    # Notify provider
    reason_text = escalation_reason == "no_work_day" ? "no tiene su agenda configurada" : "no tiene horarios disponibles"
    provider_message = "Hola #{provider.name}, un cliente quiere agendar una cita contigo pero #{reason_text}. " \
                       "Su número es: #{@from}. ¿Puedes contactarlo directamente?"

    send_provider_message(to: provider.phone,
      message: provider_message
    )

    # Send confirmation to client
    client_message = I18n.t('elisa.client.appointment.escalation_confirmed', name: provider.name)

    send_client_message(to: @from,
      message: client_message
    )

    # Clear search context
    clear_search_context

    Rails.logger.info("[ClientAssistantOrchestrator] Escalation confirmed for provider #{provider.name} (ID: #{provider.id}). Notified provider and set conversation stage to escalated.")
  end

  # Handle declined escalation - send closing message
  # @param provider_name [String] The provider's name
  def handle_escalation_declined(provider_name)
    # Send closing message
    message = "Entendido. Si cambias de opinión, puedes escribirme de nuevo. " \
              "¡Que tengas un buen día! 😊"

    send_client_message(to: @from,
      message: message
    )

    # Clear search context
    clear_search_context

    Rails.logger.info("[ClientAssistantOrchestrator] Escalation declined for provider #{provider_name}. Sent closing message to #{@from}")
  end

  # Transition from provider selection to appointment scheduling flow (C1A)
  # Creates/finds client and conversation records, then initiates appointment scheduling
  # @param provider [Provider] The selected provider
  # @param search_context [Hash] The stored search context with zone and category info
  def transition_to_appointment_flow(provider, search_context)
    # Find or create client record
    client = Client.find_or_initialize_by(phone: @from)
    if client.new_record?
      client.save!
      Rails.logger.info("[ClientAssistantOrchestrator] Created new client record for #{@from}")
    end

    # Find or create conversation record
    conversation = Conversation.find_or_create_by!(
      provider: provider,
      phone: @from,
      role: "client"
    ) do |conv|
      conv.client = client
      conv.stage = "appointment_scheduling"
      conv.context = {
        selected_zone: search_context[:selected_zone],
        selected_category: search_context[:selected_category],
        discovery_method: "c2a_region_based"
      }
      conv.last_message_at = Time.current
    end

    # Always update conversation to refresh context and stage
    conversation.update!(
      stage: "appointment_scheduling",
      context: conversation.context.merge(
        selected_zone: search_context[:selected_zone],
        selected_category: search_context[:selected_category],
        discovery_method: "c2a_region_based"
      ),
      last_message_at: Time.current
    )

    # Clear search context from Redis (no longer needed)
    clear_search_context

    # Send confirmation message
    send_client_message(to: @from,
      message: "Perfecto, seleccionaste a #{provider.name}. " \
               "Ahora vamos a agendar tu cita..."
    )

    # Query provider's WorkDay for tomorrow (or next available day)
    work_day = find_next_available_work_day(provider)

    if work_day.present?
      # WorkDay exists - proceed to show available slots (Task 18.3)
      Rails.logger.info("[ClientAssistantOrchestrator] Found WorkDay for #{provider.name} on #{work_day.date}")

      # Query existing appointments for this WorkDay
      existing_appointments = query_appointments_for_work_day(work_day)

      Rails.logger.info("[ClientAssistantOrchestrator] Found #{existing_appointments.count} existing appointments for WorkDay #{work_day.id}")

      # Generate available slots minus taken slots (Task 18.4)
      available_slots = generate_available_slots(work_day, existing_appointments)

      Rails.logger.info("[ClientAssistantOrchestrator] Generated #{available_slots.count} available slots for WorkDay #{work_day.id}")

      # Task 19.1 - Display available slots as List Message
      if available_slots.any?
        slots_payload = WhatsApp::ListMessageBuilder.build_available_slots_list(
          available_slots,
          date: work_day.date,
          provider_name: provider.name
        )

        send_client_list_message(
          to: @from,
          payload: slots_payload
        )

        # Store context for slot selection stage
        store_search_context(
          provider_id: provider.id,
          provider_name: provider.name,
          work_day_id: work_day.id,
          work_day_date: work_day.date.to_s,
          stage: "slot_selection"
        )

        Rails.logger.info("[ClientAssistantOrchestrator] Sent #{available_slots.count} available slots to #{@from} for WorkDay #{work_day.id}")
      else
        # No available slots (fully booked) - send escalation message
        send_client_message(to: @from,
          message: "Lo siento, #{provider.name} no tiene horarios disponibles para #{work_day.date == Date.tomorrow ? 'mañana' : work_day.date.strftime('%A %d de %B')}. " \
                   "¿Quieres que le avise para que te contacte directamente?"
        )

        send_client_message_with_buttons(
          to: @from,
          message: "¿Qué prefieres?",
          buttons: [
            { id: "escalate_yes", title: "Sí, avísale" },
            { id: "escalate_no", title: "No, gracias" }
          ]
        )

        # Store escalation context
        store_search_context(
          provider_id: provider.id,
          provider_name: provider.name,
          stage: "appointment_escalation",
          escalation_reason: "fully_booked"
        )

        Rails.logger.info("[ClientAssistantOrchestrator] WorkDay #{work_day.id} fully booked. Sent escalation message to #{@from}")
      end
    else
      # No WorkDay exists - show escalation message (Task 19)
      send_no_work_day_escalation(provider)
    end
  end

  # Find the provider's next available WorkDay starting from tomorrow
  # @param provider [Provider] The provider to query
  # @return [WorkDay, nil] The next available WorkDay or nil if none found
  def find_next_available_work_day(provider)
    # Start searching from tomorrow
    start_date = Date.tomorrow

    # Search for the next 7 days (reasonable window for appointment scheduling)
    (0..6).each do |days_ahead|
      search_date = start_date + days_ahead.days

      work_day = provider.work_days.find_by(date: search_date)

      # Return the first WorkDay found
      return work_day if work_day.present?
    end

    # No WorkDay found in the next 7 days
    nil
  end

  # Query existing appointments for a specific WorkDay
  # Returns appointments that are confirmed or pending (not cancelled)
  # @param work_day [WorkDay] The WorkDay to query appointments for
  # @return [ActiveRecord::Relation] Appointments for this WorkDay
  def query_appointments_for_work_day(work_day)
    # Query appointments associated with this WorkDay
    # Exclude cancelled appointments as they don't block time slots
    work_day.appointments
            .where.not(status: "cancelled")
            .order(:scheduled_at)
  end

  # Generate available time slots for a WorkDay minus taken appointment slots
  # Creates hourly slots from work_day.starts_at to work_day.ends_at
  # Excludes slots that overlap with existing appointments
  # @param work_day [WorkDay] The WorkDay to generate slots for
  # @param appointments [ActiveRecord::Relation] Existing appointments for this WorkDay
  # @return [Array<Hash>] Array of available slot hashes with :time and :display_time
  def generate_available_slots(work_day, appointments)
    # Extract start and end times from WorkDay
    start_time = work_day.starts_at
    end_time = work_day.ends_at

    # Validate that start_time and end_time are present
    if start_time.blank? || end_time.blank?
      Rails.logger.warn("[ClientAssistantOrchestrator] WorkDay #{work_day.id} missing start or end time")
      return []
    end

    # Generate all possible hourly slots
    all_slots = []
    current_time = start_time

    while current_time < end_time
      # Create a DateTime for this slot on the WorkDay's date
      slot_datetime = Time.zone.parse("#{work_day.date} #{current_time}")

      all_slots << {
        time: slot_datetime,
        display_time: slot_datetime.strftime("%H:%M") # e.g., "09:00"
      }

      # Move to next hour
      current_time += 1.hour
    end

    # Filter out slots that overlap with existing appointments OR are reserved in Redis
    available_slots = all_slots.reject do |slot|
      slot_taken?(slot[:time], appointments) ||
        !SlotReservationService.slot_available?(slot[:time], work_day.id)
    end

    available_slots
  end

  # Check if a time slot is taken by any existing appointment
  # A slot is considered taken if it falls within the appointment's time range
  # (scheduled_at to scheduled_at + estimated_duration)
  # @param slot_time [Time] The slot time to check
  # @param appointments [ActiveRecord::Relation] Existing appointments
  # @return [Boolean] True if slot is taken, false otherwise
  def slot_taken?(slot_time, appointments)
    appointments.any? do |appointment|
      appointment_start = appointment.scheduled_at
      appointment_end = appointment_start + appointment.estimated_duration.minutes

      # Check if slot_time falls within the appointment window
      slot_time >= appointment_start && slot_time < appointment_end
    end
  end

  # Send escalation message when provider has no WorkDay configured
  # @param provider [Provider] The provider with no WorkDay
  def send_no_work_day_escalation(provider)
    message = I18n.t('elisa.client.appointment.no_workday', name: provider.name)

    send_client_message_with_buttons(
      to: @from,
      message: message,
      buttons: [
        { id: "escalate_yes", title: "Sí, avísale" },
        { id: "escalate_no", title: "No, gracias" }
      ]
    )

    # Store escalation context
    store_search_context(
      provider_id: provider.id,
      provider_name: provider.name,
      stage: "appointment_escalation",
      escalation_reason: "no_work_day"
    )

    Rails.logger.info("[ClientAssistantOrchestrator] No WorkDay found for #{provider.name}. Sent escalation message to #{@from}")
  end

  # Clear search context from Redis
  def clear_search_context
    redis_key = "client_search:#{@from}"
    REDIS.del(redis_key)
  end

  # Query providers matching zone and category
  # Orders results: random, but top-rated first if > 10 results
  # @param zone [String] Selected zone name
  # @param category [String] Selected category slug
  # @return [ActiveRecord::Relation] Provider query results
  def query_providers(zone:, category:)
    # Query active providers by city (zone is part of city in our data model)
    # and category slug
    providers = Provider.where(active: true)
                       .joins(:provider_categories)
                       .where(provider_categories: { slug: category })
                       .includes(:reviews, :provider_categories)
                       .distinct

    # Filter by zone (stored in service_area or city field)
    # For now, we'll use city field as a simple match
    # TODO: Improve zone matching logic if service_area contains multiple zones
    providers = providers.where("city ILIKE ?", "%#{zone}%")

    # Order results based on count
    if providers.count > 10
      # Top-rated first, then random
      providers.left_joins(:reviews)
               .group("providers.id")
               .order(Arel.sql("COALESCE(AVG(reviews.rating), 0) DESC, RANDOM()"))
    else
      # Random order
      providers.order("RANDOM()")
    end
  end

  # Send provider results as List Message
  # @param providers [ActiveRecord::Relation] Provider query results
  # @param page [Integer] Page number
  # @param zone [String] Selected zone name
  # @param category [String] Selected category name
  def send_provider_results(providers:, page:, zone:, category:)
    # Get category name from ZonesService for display
    category_data = ZonesService.all_categories.find { |cat| cat["id"] == category }
    category_name = category_data ? category_data["name"] : category

    # Build List Message with provider results
    providers_payload = WhatsApp::ListMessageBuilder.build_provider_results_list(
      providers,
      page: page,
      zone: zone,
      category: category_name
    )

    send_client_list_message(
      to: @from,
      payload: providers_payload
    )
  end

  # Handle region detection and send confirmation message
  # @param detected_state [String] The detected state name (e.g., "Veracruz")
  def handle_region_detected(detected_state)
    greeting_message = I18n.t('elisa.client.region_detection.greeting', state: detected_state)

    # Send greeting with Quick Reply Buttons
    send_client_message_with_buttons(
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

  # Handle slot selection response from client
  # Client selected a time slot from the List Message
  # @param search_context [Hash] The stored search context with provider_id, work_day_id
  def handle_slot_selection_response(search_context)
    selected_slot_id = @body.strip # e.g., "slot_1716379200"

    # Validate slot ID format
    unless selected_slot_id.start_with?("slot_")
      send_client_message(to: @from,
        message: MessageHelper.get(:appointment, :slot_selection_error)
      )
      return
    end

    # Extract timestamp from slot ID
    slot_timestamp = selected_slot_id.gsub("slot_", "").to_i
    slot_time = Time.at(slot_timestamp)

    provider_id = search_context[:provider_id]
    provider_name = search_context[:provider_name]
    work_day_id = search_context[:work_day_id]

    # Try to reserve the slot
    reservation = SlotReservationService.reserve_slot(slot_time, work_day_id, @from)

    if reservation[:success]
      # Slot reserved successfully! Ask for confirmation
      formatted_time = slot_time.strftime("%H:%M")
      date_display = if Date.parse(search_context[:work_day_date]) == Date.tomorrow
                       "mañana"
      else
                       Date.parse(search_context[:work_day_date]).strftime("%A %d de %B")
      end

      send_client_message(to: @from,
        message: MessageHelper.get(
          :appointment,
          :slot_reserved,
          time: formatted_time,
          date: date_display
        )
      )

      send_client_message_with_buttons(
        to: @from,
        message: MessageHelper.prompt(:confirm_or_cancel),
        buttons: [
          { id: "confirm_appointment", title: MessageHelper.button(:confirm) },
          { id: "cancel_reservation", title: MessageHelper.button(:cancel) }
        ]
      )

      # Store reservation context
      store_search_context(
        provider_id: provider_id,
        provider_name: provider_name,
        work_day_id: work_day_id,
        work_day_date: search_context[:work_day_date],
        slot_time: slot_timestamp,
        slot_time_formatted: formatted_time,
        stage: "appointment_confirmation",
        reservation_expires_at: reservation[:expires_at].to_s
      )

      Rails.logger.info("[ClientAssistantOrchestrator] Reserved slot #{formatted_time} for #{@from}")
    else
      # Slot was taken by someone else - send friendly message with provider name
      provider = Provider.find_by(id: provider_id)

      send_client_message(to: @from,
        message: MessageHelper.get(
          :appointment,
          :slot_taken_by_other,
          provider_name: provider&.name || provider_name
        )
      )

      send_client_message_with_buttons(
        to: @from,
        message: MessageHelper.prompt(:confirm_or_cancel),
        buttons: [
          { id: "see_other_slots", title: MessageHelper.button(:see_slots) },
          { id: "no_thanks", title: MessageHelper.button(:no_thanks) }
        ]
      )

      # Keep context in slot_selection stage for retry
      store_search_context(
        provider_id: provider_id,
        provider_name: provider_name,
        work_day_id: work_day_id,
        work_day_date: search_context[:work_day_date],
        stage: "slot_selection_retry"
      )

      Rails.logger.info("[ClientAssistantOrchestrator] Slot #{slot_time} already reserved for #{@from}")
    end
  end

  # Handle appointment confirmation response from client
  # Client either confirms or cancels the reserved slot
  # @param search_context [Hash] The stored search context with slot_time, provider_id, work_day_id
  def handle_appointment_confirmation_response(search_context)
    slot_timestamp = search_context[:slot_time]
    slot_time = Time.at(slot_timestamp)
    provider_id = search_context[:provider_id]
    provider_name = search_context[:provider_name]
    work_day_id = search_context[:work_day_id]

    if confirmation_confirmed?(@body)
      # User confirmed - try to create appointment
      provider = Provider.find_by(id: provider_id)
      client = Client.find_or_create_by!(phone: @from)

      result = SlotReservationService.confirm_reservation(
        slot_time,
        work_day_id,
        @from,
        provider: provider,
        client: client
      )

      if result[:success]
        # Appointment created successfully
        appointment = result[:appointment]
        date_display = if appointment.scheduled_at.to_date == Date.tomorrow
                         "mañana"
        else
                         appointment.scheduled_at.strftime("%A %d de %B")
        end

        send_client_message(to: @from,
          message: MessageHelper.get(
            :appointment,
            :appointment_confirmed,
            date: date_display,
            time: appointment.scheduled_at.strftime('%H:%M')
          )
        )

        # Clear search context
        clear_search_context

        Rails.logger.info("[ClientAssistantOrchestrator] Appointment #{appointment.id} confirmed for #{@from}")
      elsif result[:reason] == :expired
        # Reservation expired - check if slot is still available
        if SlotReservationService.slot_available?(slot_time, work_day_id)
          # Slot still available - try to reserve again
          reservation = SlotReservationService.reserve_slot(slot_time, work_day_id, @from)

          if reservation[:success]
            # Re-reserved successfully - create appointment immediately
            result = SlotReservationService.confirm_reservation(
              slot_time,
              work_day_id,
              @from,
              provider: provider,
              client: client
            )

            if result[:success]
              appointment = result[:appointment]
              date_display = if appointment.scheduled_at.to_date == Date.tomorrow
                               "mañana"
              else
                               appointment.scheduled_at.strftime("%A %d de %B")
              end

              send_client_message(to: @from,
                message: MessageHelper.get(
                  :appointment,
                  :appointment_confirmed,
                  date: date_display,
                  time: appointment.scheduled_at.strftime('%H:%M')
                )
              )

              clear_search_context
              Rails.logger.info("[ClientAssistantOrchestrator] Appointment #{appointment.id} confirmed after re-reservation for #{@from}")
            end
          else
            # Someone else took it in the meantime
            send_client_message(to: @from,
              message: MessageHelper.get(:appointment, :reservation_expired_slot_taken)
            )

            send_client_message_with_buttons(
              to: @from,
              message: MessageHelper.prompt(:confirm_or_cancel),
              buttons: [
                { id: "see_other_slots", title: MessageHelper.button(:see_slots) },
                { id: "no_thanks", title: MessageHelper.button(:no_thanks) }
              ]
            )

            Rails.logger.info("[ClientAssistantOrchestrator] Slot #{slot_time} taken after expiration for #{@from}")
          end
        else
          # Slot was taken by someone else
          send_client_message(to: @from,
            message: MessageHelper.get(:appointment, :reservation_expired_slot_taken)
          )

          send_client_message_with_buttons(
            to: @from,
            message: MessageHelper.prompt(:confirm_or_cancel),
            buttons: [
              { id: "see_other_slots", title: MessageHelper.button(:see_slots) },
              { id: "no_thanks", title: MessageHelper.button(:no_thanks) }
            ]
          )

          Rails.logger.info("[ClientAssistantOrchestrator] Slot #{slot_time} taken after expiration for #{@from}")
        end
      else
        # Other error (db_conflict, validation_error, etc.)
        send_client_message(to: @from,
          message: MessageHelper.get(:appointment, :confirmation_error)
        )

        Rails.logger.error("[ClientAssistantOrchestrator] Failed to confirm appointment: #{result[:reason]}")
      end
    elsif confirmation_declined?(@body)
      # User cancelled - release reservation
      SlotReservationService.cancel_reservation(slot_time, work_day_id, @from)

      send_client_message(to: @from,
        message: MessageHelper.get(:appointment, :reservation_cancelled)
      )

      send_client_message_with_buttons(
        to: @from,
        message: MessageHelper.prompt(:confirm_or_cancel),
        buttons: [
          { id: "see_other_slots", title: MessageHelper.button(:see_slots) },
          { id: "no_thanks", title: MessageHelper.button(:no_thanks) }
        ]
      )

      Rails.logger.info("[ClientAssistantOrchestrator] Reservation cancelled by user #{@from}")
    else
      # Unclear response - ask again
      send_client_message(to: @from,
        message: MessageHelper.get(
          :appointment,
          :unclear_confirmation,
          time: search_context[:slot_time_formatted]
        )
      )

      send_client_message_with_buttons(
        to: @from,
        message: MessageHelper.prompt(:select_option),
        buttons: [
          { id: "confirm_appointment", title: MessageHelper.button(:confirm) },
          { id: "cancel_reservation", title: MessageHelper.button(:cancel) }
        ]
      )
    end
  end

  # Check if user confirmed the appointment
  # @param body [String] User's message
  # @return [Boolean] True if user confirmed
  def confirmation_confirmed?(body)
    return false if body.blank?

    normalized_body = body.downcase.strip

    # Check for button ID match
    return true if normalized_body.include?("confirm_appointment")

    # Check for natural language confirmation
    confirmation_patterns = [
      /\b(sí|si|yes|ok|dale|claro|exacto|confirmar|confirmo)\b/i
    ]

    confirmation_patterns.any? { |pattern| normalized_body.match?(pattern) }
  end

  # Check if user declined the appointment
  # @param body [String] User's message
  # @return [Boolean] True if user declined
  def confirmation_declined?(body)
    return false if body.blank?

    normalized_body = body.downcase.strip

    # Check for button ID match
    return true if normalized_body.include?("cancel_reservation")

    # Check for natural language decline
    decline_patterns = [
      /\b(no|nop|nope|cancelar|cancelo)\b/i,
      /\bno\s+(quiero|gracias)\b/i
    ]

    decline_patterns.any? { |pattern| normalized_body.match?(pattern) }
  end
end
