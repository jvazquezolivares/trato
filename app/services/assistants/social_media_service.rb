# frozen_string_literal: true

module Assistants
  # Handles the social media posting flow for providers.
  # Manages caption generation, approval, publishing, and Facebook connection.
  #
  # Called by ProviderAssistant when Claude returns a social media action.
  #
  # Usage:
  #   Assistants::SocialMediaService.call(
  #     provider: provider,
  #     action: "initiate_social_post",
  #     action_data: { "photo_url" => "https://...", "description" => "Panel eléctrico" }
  #   )
  class SocialMediaService
    CONNECT_TOKEN_TTL = 600 # 10 minutes
    CONNECT_TOKEN_PREFIX = "facebook_connect"

    def self.call(provider:, action:, action_data:)
      new(provider: provider, action: action, action_data: action_data).execute
    end

    def initialize(provider:, action:, action_data:)
      @provider = provider
      @action = action
      @action_data = action_data || {}
    end

    def execute
      case @action
      when "initiate_social_post"
        initiate_social_post
      when "generate_caption"
        generate_caption
      when "approve_caption"
        approve_and_publish
      end
    end

    private

    # Creates a Photo record from the media_url and prepares for caption generation.
    # If provider has no Facebook token, sends the connect link instead.
    def initiate_social_post
      photo = create_photo_record
      return send_connect_link unless facebook_connected?

      photo
    end

    # Generates a colloquial caption using Claude Sonnet.
    # Returns the generated caption text for provider approval.
    def generate_caption
      description = @action_data["description"] || ""
      photo_url = @action_data["photo_url"]

      response = ClaudeService.call(
        model: :sonnet,
        system_prompt: caption_system_prompt,
        user_message: build_caption_request(description, photo_url),
        context: {}
      )

      # Handle nil response
      if response.nil?
        Rails.logger.error("[SocialMediaService] Received nil response from ClaudeService")
        return {
          "message" => "Lo siento, tuve un problema generando el texto. ¿Puedes intentar de nuevo?",
          "action" => "none",
          "action_data" => {}
        }
      end

      response
    end

    # Publishes the approved caption to social media via SocialService.
    # Notifies the provider of success or failure.
    def approve_and_publish
      photo = find_photo
      return unless photo

      caption = @action_data["caption"]
      social_post = SocialService.publish(provider: @provider, photo: photo, caption: caption)

      if social_post.status == "published"
        notify_success(social_post)
      else
        notify_failure(social_post)
      end

      social_post
    end

    def create_photo_record
      @provider.photos.create!(
        url: @action_data["photo_url"],
        caption: @action_data["description"],
        category_tags: extract_category_tags
      )
    end

    def find_photo
      photo_id = @action_data["photo_id"]
      return @provider.photos.find_by(id: photo_id) if photo_id

      # Fallback: find by URL
      @provider.photos.find_by(url: @action_data["photo_url"])
    end

    def facebook_connected?
      @provider.facebook_token.present?
    end

    # Generates a temporary connect token, stores it in Redis with 10-minute TTL,
    # and sends the Facebook connect link to the provider via WhatsApp.
    def send_connect_link
      connect_token = SecureRandom.hex(16)
      redis_key = "#{CONNECT_TOKEN_PREFIX}:#{connect_token}"

      REDIS.setex(redis_key, CONNECT_TOKEN_TTL, @provider.id)

      connect_url = "#{ENV.fetch('APP_URL', 'https://trato.mx')}/connect/facebook?token=#{connect_token}"

      WhatsAppService.send_message(
        to: @provider.phone,
        message: "Para publicar en redes sociales necesito que conectes tu página de Facebook. " \
                 "Es rápido, solo toca este link 👇\n#{connect_url}"
      )

      nil
    end

    def extract_category_tags
      @provider.provider_categories.pluck(:slug)
    end

    def notify_success(social_post)
      platform_text = case social_post.platform
      when "both" then "Facebook e Instagram"
      when "facebook" then "Facebook"
      when "instagram" then "Instagram"
      end

      WhatsAppService.send_message(
        to: @provider.phone,
        message: "¡Publicado en #{platform_text}! 🎉 Tu trabajo ya está visible para más clientes."
      )
    end

    def notify_failure(social_post)
      WhatsAppService.send_message(
        to: @provider.phone,
        message: "Hubo un problema al publicar 😕 Voy a intentar de nuevo más tarde. " \
                 "Si el problema sigue, puedes reconectar tu Facebook desde tu perfil."
      )
    end

    def caption_system_prompt
      <<~PROMPT
        Eres un experto en redes sociales para trabajadores independientes en México.
        Tu trabajo es generar pies de foto atractivos para publicaciones de trabajo.

        REGLAS:
        - Responde SIEMPRE en JSON válido con estas claves:
          {
            "message": "texto del pie de foto generado",
            "action": "none",
            "action_data": {},
            "new_stage": null,
            "updated_context": {},
            "should_save_message": false,
            "intent": "caption_generated"
          }
        - El pie de foto debe ser en español mexicano coloquial
        - Máximo 2-3 líneas
        - Incluye 1-2 emojis relevantes
        - Incluye un CTA breve (ej: "¿Necesitas un electricista? Escríbeme")
        - Menciona la ciudad/zona si está disponible
        - Usa 2-3 hashtags relevantes al final
        - Tono profesional pero cálido, nunca corporativo
        - NO uses lenguaje exagerado ni promesas falsas
      PROMPT
    end

    def build_caption_request(description, _photo_url)
      parts = []
      parts << "Proveedor: #{@provider.name}"
      parts << "Categoría: #{@provider.provider_categories.pluck(:name).join(', ')}"
      parts << "Ciudad: #{@provider.city}"
      parts << "Descripción del trabajo: #{description}" if description.present?
      parts.join("\n")
    end
  end
end
