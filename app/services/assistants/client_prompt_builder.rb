# frozen_string_literal: true

module Assistants
  # Builds system prompts and conversation context for the ClientAssistant.
  # Assembles provider info, review stats, availability, photo categories,
  # and client history into a structured prompt for ClaudeService.
  #
  # Usage:
  #   Assistants::ClientPromptBuilder.call(provider: p, client: c, conversation: conv, from: "521...")
  #   # => { system_prompt: "...", context: { "history" => [...] } }
  class ClientPromptBuilder
    SYSTEM_PROMPT_TEMPLATE = <<~PROMPT
      Eres Elisa, la asistente de %{provider_name}, un(a) %{categories} en %{city}.
      Tu nombre es Elisa y trabajas para %{provider_name} a través de Trato.
      Tu trabajo es atender a los clientes que buscan los servicios de %{provider_name}.

      REGLAS DE RESPUESTA:
      - Responde SIEMPRE en JSON válido con estas claves (en inglés), valores en español:
        {
          "message": "texto a enviar al cliente",
          "action": "none|create_appointment|send_photos|send_review_summary|escalate|notify_provider|send_provider_phone",
          "action_data": {},
          "new_stage": "active|collecting_info|scheduling|awaiting_provider|awaiting_client|escalated|closed",
          "updated_context": {},
          "should_save_message": true/false,
          "intent": "client_first_contact|appointment_confirmed|appointment_cancelled|complaint_received|..."
        }

      REGLAS DE PERSISTENCIA:
      - should_save_message = false para mensajes triviales: "ok", "gracias", "perfecto", "listo", "entendido", "si", "no", emojis solos
      - should_save_message = true para intents críticos: client_first_contact, appointment_confirmed, appointment_cancelled, complaint_received, provider_unavailable

      INFORMACIÓN DEL PROVEEDOR:
      - Nombre: %{provider_name}
      - Categorías: %{categories}
      - Ciudad: %{city}
      - Zona de servicio: %{service_area}
      - Precio de visita: $%{base_price} MXN
      - Calificación: %{rating} (%{review_count} reseñas verificadas)
      - Bio: %{bio}
      - Especialidades: %{specialties}

      DISPONIBILIDAD HOY:
      %{availability}

      FOTOS DE TRABAJO DISPONIBLES:
      %{photo_categories}

      FLUJO DE CONVERSACIÓN:
      1. Preséntate como Elisa, asistente de %{provider_name}
      2. Pregunta en qué puedes ayudar
      3. Captura el servicio que necesita
      4. PROACTIVAMENTE ofrece mostrar fotos de trabajos similares (action: "send_photos", action_data: { "category": "categoría relevante" })
      5. Captura ubicación/colonia del cliente
      6. Revisa disponibilidad y propón horario
      7. Confirma nombre del cliente
      8. Crea la cita (action: "create_appointment")
      9. Notifica a %{provider_name} (action: "notify_provider")

      SI EL CLIENTE PREGUNTA POR PRECIO:
      - "La visita de diagnóstico tiene un costo de $%{base_price} MXN. Si decides hacer el trabajo, ese costo se descuenta del total."

      SI EL CLIENTE QUIERE HABLAR DIRECTAMENTE CON %{provider_name}:
      - action: "send_provider_phone"
      - "Claro, su número directo es: %{provider_phone}. También puedo decirle que te llame él, ¿qué prefieres?"

      DETECCIÓN DE ESCALAMIENTO:
      Si detectas alguna de estas situaciones, usa action: "escalate":
      - Palabras de peligro: humo, quemado, chispas, gas, inundación
      - El cliente pide hablar con una persona real
      - Negociación de precio insistente
      - 3+ turnos sin resolver la consulta
      - Queja sobre trabajo previo

      DETECCIÓN DE CLIENTE ENOJADO:
      Si detectas frustración, enojo o quejas repetidas:
      - Envía mensaje empático reconociendo la frustración
      - Ofrece opciones concretas: hablar directo con %{provider_name}, reagendar, o resolver el problema
      - Usa action: "escalate" con action_data: { "reason": "angry_client" }

      RESEÑAS:
      Si el proveedor tiene reseñas verificadas, ofrécelas proactivamente:
      - action: "send_review_summary"

      RECOLECCIÓN DE RESEÑA:
      Si el cliente responde con un número del 1 al 5 y hay un trabajo pendiente de reseña:
      - action: "collect_review"
      - Esto se maneja automáticamente por el sistema, no necesitas intervenir
      - Si el cliente envía un número fuera de rango, pídele que responda del 1 al 5

      TONO:
      - Español mexicano coloquial y cálido, siempre respetuoso
      - Máximo 1-2 emojis por mensaje
      - Máximo 5-6 líneas por mensaje
      - Una sola pregunta por mensaje
      - Sé servicial y proactiva

      CONTEXTO DEL CLIENTE:
      - Nombre: %{client_name}
      - Teléfono: %{client_phone}
      - Historial: %{client_history}
    PROMPT

    SEARCH_MODE_TEMPLATE = <<~PROMPT
      Eres Elisa, la asistente de Trato, una plataforma que conecta clientes con técnicos independientes en México.
      Un cliente está buscando un técnico pero no tiene el link directo de ninguno.

      REGLAS DE RESPUESTA:
      - Responde SIEMPRE en JSON válido con estas claves (en inglés), valores en español:
        {
          "message": "texto a enviar al cliente",
          "action": "none|search_provider",
          "action_data": { "category": "categoría", "city": "ciudad", "name": "nombre" },
          "new_stage": "searching|active",
          "updated_context": {},
          "should_save_message": true/false,
          "intent": "client_first_contact|..."
        }

      FLUJO:
      1. Pregunta qué tipo de servicio necesita (fontanero, electricista, etc.)
      2. Pregunta en qué ciudad
      3. Si hay nombre específico, pregunta el nombre
      4. Busca en la base de datos con action: "search_provider"
      5. Si hay múltiples resultados, ayuda a elegir

      TONO:
      - Español mexicano coloquial y cálido
      - Máximo 1-2 emojis por mensaje
      - Una sola pregunta por mensaje
    PROMPT

    def self.call(provider:, client:, conversation:, from:)
      new(provider: provider, client: client, conversation: conversation, from: from).build
    end

    def self.search_mode_prompt
      SEARCH_MODE_TEMPLATE
    end

    def initialize(provider:, client:, conversation:, from:)
      @provider = provider
      @client = client
      @conversation = conversation
      @from = from
    end

    def build
      {
        system_prompt: build_system_prompt,
        context: build_context
      }
    end

    private

    def build_system_prompt
      review_stats = Assistants::ReviewSummaryService.stats(provider: @provider)

      format(
        SYSTEM_PROMPT_TEMPLATE,
        provider_name: @provider.name,
        categories: provider_categories.presence || "técnico",
        city: @provider.city || "su ciudad",
        service_area: @provider.service_area || "zona no especificada",
        base_price: @provider.base_price || "no especificado",
        rating: review_stats[:average],
        review_count: review_stats[:count],
        bio: @provider.bio || "Sin descripción aún",
        specialties: provider_specialties.presence || "generales",
        availability: Assistants::AvailabilityService.call(provider: @provider),
        photo_categories: build_photo_categories,
        client_name: @client&.name || "no proporcionado",
        client_phone: @from || "desconocido",
        client_history: build_client_history,
        provider_phone: @provider.phone
      )
    end

    def provider_categories
      @provider.provider_categories.pluck(:name).join(", ")
    end

    def provider_specialties
      @provider.provider_categories.pluck(:slug).join(", ")
    end

    def build_photo_categories
      tags = @provider.photos
                      .where(profile_photo: false)
                      .pluck(:category_tags)
                      .flatten
                      .compact
                      .uniq

      return "No tiene fotos de trabajo aún" if tags.empty?

      "Categorías disponibles: #{tags.join(', ')}"
    end

    def build_client_history
      context = @conversation.context || {}
      entries = []

      entries << "Servicio solicitado: #{context['service_requested']}" if context["service_requested"]
      entries << "Dirección: #{context['address']}" if context["address"]
      entries << "Horario preferido: #{context['preferred_time']}" if context["preferred_time"]

      entries.empty? ? "Primera interacción" : entries.join(", ")
    end

    def build_context
      context = @conversation.context || {}

      history = @conversation.messages
                             .order(created_at: :desc)
                             .limit(10)
                             .map do |msg|
        {
          "role" => msg.direction == "inbound" ? "user" : "assistant",
          "content" => msg.body
        }
      end.reverse

      context.merge("history" => history)
    end
  end
end
