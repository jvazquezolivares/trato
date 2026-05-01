# frozen_string_literal: true

module Assistants
  # Handles the search mode flow when a client is looking for a provider
  # by category, city, or name. Manages Redis-backed search state.
  #
  # Usage:
  #   Assistants::ProviderSearchService.call(from: "521...", body: "Busco fontanero")
  class ProviderSearchService
    REDIS_TTL = 86_400 # 24 hours

    def self.call(from:, body:)
      new(from: from, body: body).process
    end

    def initialize(from:, body:)
      @from = from
      @body = body
    end

    def process
      response = call_claude
      execute_search_action(response)
      send_reply(response)

      response
    end

    private

    def call_claude
      ClaudeService.call(
        model: :haiku,
        system_prompt: Assistants::ClientPromptBuilder.search_mode_prompt,
        user_message: @body,
        context: load_context
      )
    end

    def load_context
      raw = REDIS.get(redis_key)
      return {} unless raw

      JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    def execute_search_action(response)
      action_data = response["action_data"] || {}

      if response["action"] == "search_provider"
        results = search_providers(action_data)
        handle_results(results)
      end

      save_context(response)
    end

    def search_providers(action_data)
      scope = Provider.where(active: true)

      scope = scope.where("LOWER(city) LIKE ?", "%#{action_data['city']&.downcase}%") if action_data["city"].present?

      if action_data["category"].present?
        scope = scope.joins(:provider_categories)
                     .where("LOWER(provider_categories.name) LIKE ?", "%#{action_data['category']&.downcase}%")
      end

      if action_data["name"].present?
        scope = scope.where("LOWER(name) LIKE ?", "%#{action_data['name']&.downcase}%")
      end

      scope.distinct.limit(5)
    end

    def handle_results(results)
      if results.empty?
        send_no_results_message
      elsif results.one?
        transition_to_provider(results.first)
      else
        send_multiple_results(results)
      end
    end

    def send_no_results_message
      WhatsAppService.send_message(
        to: @from,
        message: "No encontré técnicos con esos datos. ¿Puedes darme más detalles como la ciudad o el tipo de servicio?"
      )
    end

    def transition_to_provider(provider)
      REDIS.del(redis_key)

      categories = provider.provider_categories.pluck(:name).join(" y ")
      WhatsAppService.send_message(
        to: @from,
        message: "Hola, soy Elisa, la asistente de #{provider.name}, " \
                 "#{categories} en #{provider.city}. " \
                 "¿En qué te puedo ayudar? 😊"
      )
    end

    def send_multiple_results(results)
      provider_list = results.map.with_index(1) do |provider, index|
        "#{index}. #{provider.name} — #{provider.provider_categories.pluck(:name).join(', ')} en #{provider.city}"
      end.join("\n")

      WhatsAppService.send_message(
        to: @from,
        message: "Encontré estos técnicos:\n\n#{provider_list}\n\n¿Con cuál te gustaría contactar?"
      )

      save_results(results)
    end

    def send_reply(response)
      message = response["message"]
      return if message.blank? || @from.blank?

      WhatsAppService.send_message(to: @from, message: message)
    end

    def save_context(response)
      context = response["updated_context"] || {}
      context["stage"] = response["new_stage"] if response["new_stage"]

      REDIS.setex(redis_key, REDIS_TTL, context.to_json)
    end

    def save_results(results)
      context = load_context.merge("search_results" => results.map(&:id))
      REDIS.setex(redis_key, REDIS_TTL, context.to_json)
    end

    def redis_key
      "search_state:#{@from}"
    end
  end
end
