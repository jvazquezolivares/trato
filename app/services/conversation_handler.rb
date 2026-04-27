# frozen_string_literal: true

# Central router for all incoming WhatsApp messages.
# Determines the correct conversational flow based on sender identity:
#   1. Known provider phone → ProviderAssistant
#   2. Message body matches a provider short_uuid → ClientAssistant
#   3. Unknown sender → welcome / onboarding flow via Redis state
#
# Pre-provider state lives in Redis (key: "onboarding_state:{phone}", 24h TTL)
# because the Conversation model requires a provider_id (NOT NULL).
class ConversationHandler
  WELCOME_MESSAGE = "¿Estás buscando un técnico o quieres darte de alta como técnico? " \
                    "Responde *1* para buscar un técnico o *2* para registrarte."
  ONBOARDING_TTL = 86_400 # 24 hours in seconds

  def self.call(from:, body:, media_url: nil)
    return route_to_provider(from, body, media_url) if provider_by_phone(from)
    return route_to_client(body) if provider_by_short_uuid(body)

    handle_unknown(from: from, body: body)
  end

  def self.handle_unknown(from:, body:)
    state = load_onboarding_state(from)

    return send_welcome_and_store_state(from) if state.nil? || state["stage"] == "new"
    return handle_onboarding_welcome(from, body, state) if state["stage"] == "onboarding_welcome"
    return OnboardingService.call(from: from, body: body) if state["stage"] == "onboarding"
  end

  # --- Private helpers ---

  def self.provider_by_phone(phone)
    @_provider_by_phone = Provider.find_by(phone: phone)
  end

  def self.provider_by_short_uuid(body)
    return nil if body.blank?

    @_provider_by_uuid = Provider.find_by(short_uuid: body.strip)
  end

  def self.route_to_provider(from, body, media_url)
    ProviderAssistant.call(provider: @_provider_by_phone, body: body, media_url: media_url)
  end

  def self.route_to_client(body)
    ClientAssistant.call(provider: @_provider_by_uuid, from: nil, body: body)
  end

  def self.load_onboarding_state(phone)
    raw = REDIS.get("onboarding_state:#{phone}")
    return nil unless raw

    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def self.send_welcome_and_store_state(phone)
    WhatsAppService.send_message(to: phone, message: WELCOME_MESSAGE)
    REDIS.setex("onboarding_state:#{phone}", ONBOARDING_TTL, { stage: "onboarding_welcome" }.to_json)
  end

  def self.handle_onboarding_welcome(from, body, _state)
    normalized = body&.strip

    case normalized
    when "2"
      OnboardingService.call(from: from, body: body)
    when "1"
      ClientAssistant.call_search_mode(from: from, body: body)
    else
      WhatsAppService.send_message(to: from, message: WELCOME_MESSAGE)
    end
  end

  private_class_method :provider_by_phone, :provider_by_short_uuid,
                       :route_to_provider, :route_to_client,
                       :load_onboarding_state, :send_welcome_and_store_state,
                       :handle_onboarding_welcome
end
