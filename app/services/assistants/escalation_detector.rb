# frozen_string_literal: true

module Assistants
  # Detects danger keywords and escalation triggers in client messages.
  # Covers 20+ trades: electricista, plomero, gasista, albañil, carpintero,
  # herrero, soldador, técnico de refrigeración, electrodomésticos, etc.
  #
  # Builds structured escalation messages for provider notification.
  # Future: migrate keyword catalog to an editable DB table.
  #
  # Usage:
  #   Assistants::EscalationDetector.call(body: "hay humo en mi casa", ...)
  #   # => { detected: true, reason: "danger" }
  class EscalationDetector
    DANGER_KEYWORDS = [
      # Eléctricos — electricista, electrónico, técnico de computadoras
      "humo", "quemado", "chispas", "cortocircuito", "descarga",
      "electrocutado", "se prendió", "se prendio", "olor a quemado",
      "cable derretido", "apagón", "apagon", "fundido", "tronó", "trono",

      # Gas y fuego — plomero, gasista, instalador
      "gas", "fuga de gas", "olor a gas", "incendio", "fuego", "llamas",
      "explosión", "explosion", "se quema", "ardiendo",

      # Agua — plomero, fontanero, impermeabilizador
      "inundación", "inundacion", "se reventó", "se revento",
      "fuga de agua", "se desbordó", "se desbordo", "goteo fuerte",
      "se rompió la tubería", "se rompio la tuberia",
      "agua por todos lados",

      # Estructural — albañil, carpintero, herrero
      "se cayó", "se cayo", "derrumbe", "grieta grande",
      "se colapsó", "se colapso", "se desplomó", "se desplomo",
      "crujido fuerte", "se partió", "se partio",

      # Electrodomésticos / electrónica — reparación, técnico
      "explotó", "exploto", "sacó chispas", "saco chispas",
      "se calentó mucho", "se calento mucho", "huele a quemado",
      "derritió", "derritio",

      # Clima y refrigeración — técnico de aire acondicionado
      "fuga de refrigerante", "olor raro", "congelado",
      "hielo en el equipo",

      # General / emergencia — todos los oficios
      "emergencia", "urgente", "peligro", "auxilio", "ayuda urgente",
      "me lastimé", "me lastime", "herida", "sangre", "ambulancia",
      "bomberos", "atrapado", "no puedo respirar", "me caí", "me cai",
      "accidente"
    ].freeze

    SPEAK_PATTERNS = [
      "hablar con una persona", "hablar con alguien", "quiero hablar con",
      "necesito hablar con", "pásame con", "pasame con",
      "comunicarme con", "persona real"
    ].freeze

    PRICE_NEGOTIATION_PATTERNS = [
      "muy caro", "más barato", "mas barato", "descuento", "rebaja",
      "cobras mucho", "no me alcanza", "precio más bajo", "precio mas bajo",
      "bajar el precio", "negociar el precio"
    ].freeze

    COMPLAINT_PATTERNS = [
      "mal trabajo", "quedó mal", "quedo mal", "no sirve", "no funciona",
      "se volvió a", "se volvio a", "otra vez el mismo",
      "no quedé satisf", "no quede satisf", "reclamo", "queja"
    ].freeze

    def self.call(body:, from:, provider:, conversation:)
      new(body: body, from: from, provider: provider, conversation: conversation).detect
    end

    def self.escalate!(conversation:, provider:, from:, body:, reason:, detail: nil)
      new(body: body, from: from, provider: provider, conversation: conversation)
        .escalate!(reason: reason, detail: detail)
    end

    def initialize(body:, from:, provider:, conversation:)
      @body = body
      @from = from
      @provider = provider
      @conversation = conversation
    end

    def detect
      return no_escalation if @body.blank?

      normalized = @body.downcase

      return escalate("danger") if danger_detected?(normalized)
      return escalate("speak_with_person") if speak_request?(normalized)
      return escalate("price_negotiation") if price_negotiation?(normalized)
      return escalate("complaint") if complaint_detected?(normalized)

      no_escalation
    end

    def escalate!(reason:, detail: nil)
      @conversation.update!(stage: "escalated")

      # For danger situations with a client, send emergency-specific alerts to both parties
      if reason == "danger" && @conversation.client.present?
        send_client_emergency_alert
        send_provider_emergency_alert
      else
        # For non-danger escalations, send general alert to provider only
        provider_message = build_escalation_message(reason, detail)
        WhatsAppService.send_message(
          to: @provider.phone,
          message: provider_message,
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )
      end
    end

    private

    def danger_detected?(normalized_body)
      DANGER_KEYWORDS.any? do |keyword|
        if keyword.include?(" ") || keyword.length > 5
          normalized_body.include?(keyword)
        else
          normalized_body.match?(/\b#{Regexp.escape(keyword)}\b/)
        end
      end
    end

    def speak_request?(normalized_body)
      SPEAK_PATTERNS.any? { |pattern| normalized_body.include?(pattern) }
    end

    def price_negotiation?(normalized_body)
      PRICE_NEGOTIATION_PATTERNS.any? { |pattern| normalized_body.include?(pattern) }
    end

    def complaint_detected?(normalized_body)
      COMPLAINT_PATTERNS.any? { |pattern| normalized_body.include?(pattern) }
    end

    def escalate(reason)
      { detected: true, reason: reason }
    end

    def no_escalation
      { detected: false, reason: nil }
    end

    def send_client_emergency_alert
      client = @conversation.client
      client_name = client.name || "Cliente"

      message = I18n.t(
        'elisa.client.emergency.client_alert',
        name: client_name,
        provider_name: @provider.name,
        phone: @provider.phone
      )

      WhatsAppService.send_message(
        to: @from,
        message: message,
        phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
      )

      Rails.logger.info(
        "[EscalationDetector] Sent emergency alert to client #{@from} " \
        "for provider #{@provider.name}"
      )
    end

    def send_provider_emergency_alert
      client = @conversation.client
      client_name = client.name || "Cliente"

      # Extract the detected keyword from the body
      detected_keyword = extract_danger_keyword(@body.downcase)

      message = I18n.t(
        'elisa.client.emergency.provider_alert',
        name: client_name,
        keyword: detected_keyword,
        phone: @from
      )

      WhatsAppService.send_message(
        to: @provider.phone,
        message: message,
        phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
      )

      Rails.logger.info(
        "[EscalationDetector] Sent emergency alert to provider #{@provider.phone} " \
        "about client #{client_name} (#{@from})"
      )
    end

    def extract_danger_keyword(normalized_body)
      # Sort keywords by length (longest first) to match multi-word phrases before single words
      sorted_keywords = DANGER_KEYWORDS.sort_by { |k| -k.length }

      # Find the first matching danger keyword in the message
      matched_keyword = sorted_keywords.find do |keyword|
        if keyword.include?(" ") || keyword.length > 5
          normalized_body.include?(keyword)
        else
          normalized_body.match?(/\b#{Regexp.escape(keyword)}\b/)
        end
      end

      matched_keyword || "una emergencia"
    end

    def build_escalation_message(reason, detail)
      context_summary = "📍 Teléfono del cliente: #{@from}"

      case reason
      when "danger"
        "🚨 *URGENTE — Posible emergencia*\n\n" \
        "Un cliente reportó una situación que puede ser peligrosa:\n" \
        "\"#{@body}\"\n\n#{context_summary}\n\n" \
        "Te recomiendo contactarle directamente lo antes posible."
      when "angry_client"
        "⚠️ *Cliente molesto*\n\n" \
        "Un cliente expresó frustración o enojo:\n" \
        "\"#{@body}\"\n\n#{context_summary}\n\n" \
        "Te recomiendo contactarle para resolver la situación."
      when "speak_with_person"
        "📞 *Cliente quiere hablar contigo*\n\n" \
        "Un cliente pidió hablar directamente contigo.\n" \
        "\"#{@body}\"\n\n#{context_summary}"
      when "price_negotiation"
        "💰 *Negociación de precio*\n\n" \
        "Un cliente está negociando el precio:\n" \
        "\"#{@body}\"\n\n#{context_summary}\n\n" \
        "Esto es mejor que lo manejes tú directamente."
      when "unresolved_turns"
        "🔄 *Conversación sin resolver*\n\n" \
        "Llevo varios turnos sin poder resolver la consulta de un cliente.\n" \
        "\"#{@body}\"\n\n#{context_summary}\n\n" \
        "¿Puedes ayudarme con este caso?"
      when "complaint"
        "📝 *Queja de cliente*\n\n" \
        "Un cliente tiene una queja sobre un trabajo previo:\n" \
        "\"#{@body}\"\n\n#{context_summary}\n\n" \
        "Te recomiendo contactarle para resolver."
      else
        "⚠️ *Atención requerida*\n\n" \
        "#{detail || 'Se requiere tu atención con un cliente.'}\n" \
        "\"#{@body}\"\n\n#{context_summary}"
      end
    end
  end
end
