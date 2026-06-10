# frozen_string_literal: true

# Central router for messages sent to the PROVIDER WhatsApp number.
# Determines the correct conversational flow based on sender identity:
#   1. Known provider phone → ProviderAssistant
#   2. Unknown sender → welcome / onboarding flow via Redis state
#
# Note: Client messages are handled separately via ClientMessageJob → ClientAssistantOrchestrator
# since clients now message a separate client WhatsApp number.
#
# Pre-provider state lives in Redis (key: "onboarding_state:{phone}", 24h TTL)
# because the Conversation model requires a provider_id (NOT NULL).
class ProviderConversationHandler
  ONBOARDING_TTL = 86_400 # 24 hours in seconds

  def self.call(from:, body:, media_url: nil)
    Rails.logger.info("[ProviderConversationHandler] Mensaje recibido de: #{from}, body: #{body&.truncate(50)}")

    provider = provider_by_phone(from)

    if provider
      Rails.logger.info("[ProviderConversationHandler] Provider encontrado: #{provider.name} (ID: #{provider.id})")
      return route_to_provider(from, body, media_url)
    end

    Rails.logger.info("[ProviderConversationHandler] Provider no encontrado. Rutear a handle_unknown")
    handle_unknown(from: from, body: body)
  end

  def self.handle_unknown(from:, body:)
    state = load_onboarding_state(from)
    Rails.logger.info("[ProviderConversationHandler] Estado Redis para #{from}: #{state.inspect}")

    # If no state exists, send welcome message and initialize onboarding
    if state.nil? || state["stage"] == "new"
      Rails.logger.info("[ProviderConversationHandler] Enviando mensaje de bienvenida a #{from}")
      return send_welcome_and_store_state(from)
    end

    # All subsequent messages proceed directly to onboarding
    # No routing question stage needed since dual numbers handle provider/client separation
    if onboarding_in_progress?(state)
      Rails.logger.info("[ProviderConversationHandler] Onboarding en progreso. Llamando a OnboardingService")
      OnboardingService.call(from: from, body: body)
    else
      Rails.logger.warn("[ProviderConversationHandler] Estado inesperado: #{state['stage']}")
    end
  end

  def self.onboarding_in_progress?(state)
    stage = state["stage"]
    # Include onboarding_welcome stage since it now proceeds directly to onboarding
    stage == "onboarding_welcome" ||
      stage == "onboarding" ||
      stage&.start_with?("collecting_", "bio_", "explaining_") ||
      stage == "complete"
  end

  # --- Private helpers ---

  def self.provider_by_phone(phone)
    @_provider_by_phone = Provider.includes(
      :provider_categories,
      :work_days,
      :tasks,
      provider_clients: :client,
      jobs: :client
    ).find_by(phone: phone)
  end

  def self.route_to_provider(from, body, media_url)
    ProviderAssistant.call(provider: @_provider_by_phone, body: body, media_url: media_url)
  end

  def self.load_onboarding_state(phone)
    raw = REDIS.get("onboarding_state:#{phone}")
    return nil unless raw

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def self.send_welcome_and_store_state(phone)
    WhatsAppService.send_message(
      to: phone,
      message: I18n.t('elisa.provider.onboarding.welcome'),
      phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
    )
    REDIS.setex("onboarding_state:#{phone}", ONBOARDING_TTL, { stage: "onboarding_welcome" }.to_json)
  end

  private_class_method :provider_by_phone,
                       :route_to_provider,
                       :load_onboarding_state, :send_welcome_and_store_state,
                       :onboarding_in_progress?
end
