# frozen_string_literal: true

# Guides unknown numbers through provider registration via WhatsApp.
#
# Uses Redis (key: "onboarding_state:{phone}") to track field collection
# progress because the Conversation model requires a provider_id (NOT NULL).
# Once the Provider record is created, a Conversation record is created in the DB.
#
# State machine stages (stored in Redis as JSON):
#   onboarding          → initial confirmation
#   collecting_name     → ask for name
#   collecting_categories → ask for service categories
#   collecting_city     → ask for city
#   collecting_area     → ask for service area
#   collecting_price    → ask for visit price
#   collecting_experience → ask for years of experience
#   collecting_specialties → ask for specialties
#   collecting_specialized_work → ask for specialized work
#   bio_questions       → ask 3-4 conversational questions for bio generation
#   bio_review          → present generated bio for approval
#   collecting_profile_photo → request profile photo (optional)
#   collecting_work_photos → request work photos (optional)
#   explaining_facebook → explain Facebook benefit, request page URL
#   collecting_email    → request email (optional)
#   complete            → provider created, send confirmation
#
# All data is stored in Redis under the "data" key as a Hash with English keys.
# Values are in Spanish (as provided by the user).
class OnboardingService
  REDIS_KEY_PREFIX = "onboarding_state"
  REDIS_TTL = 86_400 # 24 hours
  MAX_BIO_REVISIONS = 2

  FIELD_COLLECTION_STAGES = %w[
    collecting_name
    collecting_categories
    collecting_city
    collecting_area
    collecting_price
    collecting_experience
    collecting_specialties
    collecting_specialized_work
  ].freeze

  def self.call(from:, body:)
    new(from: from, body: body).process
  end

  def initialize(from:, body:)
    @from = from
    @body = body&.strip
    @state = load_state
  end

  def process
    stage = @state["stage"]

    case stage
    when "onboarding_welcome", "onboarding"
      start_field_collection
    when "collecting_name"
      collect_name
    when "collecting_categories"
      collect_categories
    when "collecting_city"
      collect_city
    when "collecting_area"
      collect_area
    when "collecting_price"
      collect_price
    when "collecting_experience"
      collect_experience
    when "collecting_specialties"
      collect_specialties
    when "collecting_specialized_work"
      collect_specialized_work
    when "bio_questions"
      collect_bio_answers
    when "bio_review"
      handle_bio_review
    when "collecting_profile_photo"
      handle_profile_photo
    when "collecting_work_photos"
      handle_work_photos
    when "explaining_facebook"
      handle_facebook_url
    when "collecting_email"
      handle_email
    else
      start_field_collection
    end
  end

  private

  # --- State management (Redis) ---

  def load_state
    raw = REDIS.get(redis_key)
    return default_state unless raw

    JSON.parse(raw)
  rescue JSON::ParserError
    default_state
  end

  def default_state
    { "stage" => "onboarding", "data" => {} }
  end

  def save_state
    REDIS.setex(redis_key, REDIS_TTL, @state.to_json)
  end

  def redis_key
    "#{REDIS_KEY_PREFIX}:#{@from}"
  end

  def data
    @state["data"] ||= {}
  end

  def advance_to(stage, message:)
    @state["stage"] = stage
    save_state
    send_message(message)
  end

  def send_message(message)
    WhatsAppService.send_message(to: @from, message: message)
  end

  # --- Field collection stages ---

  def start_field_collection
    advance_to("collecting_name", message: "¡Qué bueno que quieres registrarte! 🎉 ¿Cómo te llamas?")
  end

  def collect_name
    return send_message("Necesito tu nombre para continuar. ¿Cómo te llamas?") if @body.blank?

    data["name"] = @body
    advance_to(
      "collecting_categories",
      message: "Mucho gusto, #{@body} 👋 ¿A qué te dedicas? Puedes mencionar varios oficios, por ejemplo: fontanero, electricista, albañil."
    )
  end

  def collect_categories
    return send_message("¿A qué te dedicas? Puedes mencionar varios oficios.") if @body.blank?

    data["categories"] = parse_categories(@body)
    advance_to(
      "collecting_city",
      message: "¿En qué ciudad trabajas?"
    )
  end

  def collect_city
    return send_message("¿En qué ciudad trabajas?") if @body.blank?

    data["city"] = @body
    advance_to(
      "collecting_area",
      message: "¿En qué zonas o colonias de #{@body} das servicio? Puedes mencionar varias."
    )
  end

  def collect_area
    return send_message("¿En qué zonas o colonias das servicio?") if @body.blank?

    data["service_area"] = @body
    advance_to(
      "collecting_price",
      message: "¿Cuánto cobras por visita de diagnóstico? (en pesos MXN)"
    )
  end

  def collect_price
    return send_message("¿Cuánto cobras por visita de diagnóstico? Solo pon el número en pesos.") if @body.blank?

    data["base_price"] = extract_price(@body)
    advance_to(
      "collecting_experience",
      message: "¿Cuántos años de experiencia tienes?"
    )
  end

  def collect_experience
    return send_message("¿Cuántos años de experiencia tienes?") if @body.blank?

    data["years_experience"] = @body
    advance_to(
      "collecting_specialties",
      message: "¿Hay algo en lo que te especialices? Por ejemplo: urgencias, instalaciones nuevas, reparaciones..."
    )
  end

  def collect_specialties
    return send_message("¿En qué te especializas?") if @body.blank?

    data["specialties"] = @body
    advance_to(
      "collecting_specialized_work",
      message: "¿Haces algún trabajo especializado? Por ejemplo: calentadores solares, sistemas de alta presión, paneles eléctricos..."
    )
  end

  def collect_specialized_work
    return send_message("¿Haces algún trabajo especializado?") if @body.blank?

    data["specialized_work"] = @body
    data["bio_answers"] = []
    data["bio_question_index"] = 0

    ask_next_bio_question
  end

  # --- Bio generation flow ---

  BIO_QUESTIONS = [
    "¿Qué es lo que más te gusta de tu trabajo?",
    "¿Cuál ha sido el trabajo más interesante que has hecho?",
    "¿Qué te diferencia de otros técnicos en tu zona?",
    "¿Hay algo que quieras que tus clientes sepan de ti?"
  ].freeze

  def ask_next_bio_question
    index = data["bio_question_index"].to_i

    if index >= BIO_QUESTIONS.length
      generate_bio
      return
    end

    advance_to("bio_questions", message: BIO_QUESTIONS[index])
  end

  def collect_bio_answers
    return send_message(BIO_QUESTIONS[data["bio_question_index"].to_i]) if @body.blank?

    data["bio_answers"] << @body
    data["bio_question_index"] = data["bio_question_index"].to_i + 1

    ask_next_bio_question
  end

  def generate_bio
    @state["stage"] = "bio_review"
    data["bio_revision_count"] = 0

    response = ClaudeService.call(
      model: :sonnet,
      system_prompt: bio_system_prompt,
      user_message: bio_user_message,
      context: {}
    )

    generated_bio = response["message"] || response["bio"] || response.values.first
    data["generated_bio"] = generated_bio
    save_state

    send_message(generated_bio)
    send_message("¿Te gusta esta descripción? Responde *sí* para aprobarla o dime qué le cambiarías.")
  end

  def handle_bio_review
    if data["awaiting_dictated_bio"]
      # Provider is dictating their own bio after 2 failed revisions
      data["bio"] = @body
      data.delete("awaiting_dictated_bio")
      advance_to(
        "collecting_profile_photo",
        message: "Listo, usaré esa descripción 👍 Ahora, ¿me puedes mandar una foto tuya para tu perfil? Es opcional. Si no quieres, escribe *no*."
      )
    elsif affirmative_response?(@body)
      data["bio"] = data["generated_bio"]
      advance_to(
        "collecting_profile_photo",
        message: "¡Perfecto! Ahora, ¿me puedes mandar una foto tuya para tu perfil? Es opcional, pero ayuda mucho a generar confianza. Si no quieres, escribe *no*."
      )
    else
      revision_count = data["bio_revision_count"].to_i + 1
      data["bio_revision_count"] = revision_count

      if revision_count >= MAX_BIO_REVISIONS
        # After 2 failed attempts, ask provider to dictate bio directly
        data["awaiting_dictated_bio"] = true
        advance_to(
          "bio_review",
          message: "Entiendo que no quedó como quieres. Mejor dime con tus propias palabras cómo te gustaría que dijera tu descripción y la uso tal cual."
        )
      else
        regenerate_bio_with_feedback
      end
    end
  end

  def regenerate_bio_with_feedback
    response = ClaudeService.call(
      model: :sonnet,
      system_prompt: bio_system_prompt,
      user_message: "El usuario pidió estos cambios a la bio anterior: #{@body}\n\nBio anterior: #{data['generated_bio']}",
      context: {}
    )

    generated_bio = response["message"] || response["bio"] || response.values.first
    data["generated_bio"] = generated_bio
    save_state

    send_message(generated_bio)
    send_message("¿Ahora sí te gusta? Responde *sí* para aprobarla o dime qué le cambiarías.")
  end

  # --- Photo collection ---

  def handle_profile_photo
    if negative_response?(@body)
      advance_to(
        "collecting_work_photos",
        message: "Sin problema. ¿Tienes fotos de tus trabajos que quieras compartir? Ayudan mucho a que los clientes vean tu trabajo. Si no tienes ahorita, escribe *no*."
      )
    else
      # For now, acknowledge photo receipt (media handling is via media_url in webhook)
      data["has_profile_photo"] = true
      save_state
      advance_to(
        "collecting_work_photos",
        message: "¡Buena foto! 📸 ¿Tienes fotos de tus trabajos? Mándame las que quieras. Cuando termines, escribe *listo*."
      )
    end
  end

  def handle_work_photos
    if negative_response?(@body) || done_response?(@body)
      advance_to(
        "explaining_facebook",
        message: "Conectar tu página de Facebook tiene una ventaja: yo puedo publicar automáticamente tus fotos de trabajo y actualizaciones en tu página, sin que tú tengas que hacer nada 📱 ¿Tienes una página de Facebook de tu negocio? Si sí, mándame el link. Si no, escribe *no*."
      )
    else
      data["work_photos_count"] = (data["work_photos_count"].to_i) + 1
      save_state
      send_message("¡Guardada! Mándame más fotos o escribe *listo* cuando termines.")
    end
  end

  # --- Facebook and email ---

  def handle_facebook_url
    if negative_response?(@body)
      data["facebook_page_url"] = nil
    else
      data["facebook_page_url"] = @body
    end

    advance_to(
      "collecting_email",
      message: "¿Me das tu correo electrónico? Es opcional, pero lo uso para enviarte reportes y notificaciones importantes. Si no quieres, escribe *no*."
    )
  end

  def handle_email
    if negative_response?(@body)
      data["email"] = nil
    else
      data["email"] = @body
    end

    create_provider_and_complete
  end

  # --- Provider creation ---

  def create_provider_and_complete
    provider = build_provider
    create_categories(provider)
    provider.slug = provider.build_slug
    provider.save!

    # Clean up Redis state — provider now exists in DB
    REDIS.del(redis_key)

    send_confirmation(provider)
    send_capabilities_explanation(provider)
    send_auto_reply_suggestion(provider)
  end

  def build_provider
    Provider.new(
      name: data["name"],
      phone: @from,
      short_uuid: SecureRandom.hex(4),
      city: data["city"],
      service_area: data["service_area"],
      base_price: data["base_price"].to_d,
      bio: data["bio"],
      email: data["email"],
      facebook_page_url: data["facebook_page_url"],
      active: true,
      onboarded_at: Time.current
    )
  end

  def create_categories(provider)
    categories = data["categories"] || []
    categories.each_with_index do |category_name, index|
      provider.provider_categories.build(
        name: category_name.strip.capitalize,
        slug: category_name.strip.downcase.parameterize,
        primary: index.zero?
      )
    end
  end

  def send_confirmation(provider)
    profile_url = "trato.mx/p/#{provider.slug}"
    assistant_link = provider.assistant_whatsapp_link

    message = "¡Listo, #{provider.name}! Tu perfil ya está activo 🎉\n\n" \
              "Tu página: #{profile_url}\n" \
              "Link de tu asistente: #{assistant_link}\n\n" \
              "Comparte ese link con tus clientes para que me escriban a mí cuando no puedas contestar."

    send_message(message)
  end

  def send_capabilities_explanation(provider)
    messages = [
      "Te cuento lo que puedo hacer por ti 👇",
      "📅 *Agenda:* Dime cuándo empiezas a trabajar y yo organizo tus citas del día. Tus clientes pueden agendar conmigo directo.",
      "💰 *Cobros y gastos:* Cuando termines un trabajo, cuéntame y yo registro el cobro. También puedo llevar tus gastos de material.",
      "📋 *Pendientes:* Si me dices \"recuérdame comprar cable\" o \"tengo que llamar al señor Pérez\", yo te lo recuerdo al día siguiente.",
      "👥 *Atención a clientes:* Cuando no puedas contestar, yo atiendo a tus clientes, les muestro fotos de tu trabajo y agendo citas.",
      "📊 *Finanzas:* Pregúntame \"¿cuánto llevo hoy?\" o \"¿cuánto me deben?\" y te doy el resumen al instante.",
      "📱 *Redes sociales:* Mándame una foto de tu trabajo y yo la publico en tu Facebook con un texto profesional."
    ]

    WhatsAppService.send_multipart(to: @from, messages: messages)
  end

  def send_auto_reply_suggestion(provider)
    auto_reply = "Por cierto, te recomiendo poner este mensaje como respuesta automática en tu WhatsApp Business:\n\n" \
                 "\"Hola 👋 Ahorita estoy trabajando.\n" \
                 "Mi asistente puede ayudarte:\n" \
                 "#{provider.assistant_whatsapp_link}\""

    send_message(auto_reply)
  end

  # --- Helper methods ---

  def parse_categories(text)
    # Split by common separators: commas, "y", "e", newlines
    text.split(/[,\n]|(?:\s+y\s+)|(?:\s+e\s+)/)
        .map(&:strip)
        .reject(&:blank?)
  end

  def extract_price(text)
    # Extract numeric value from text like "$300", "300 pesos", "trescientos"
    numeric = text.gsub(/[^\d.]/, "")
    numeric.present? ? numeric : text
  end

  def affirmative_response?(text)
    return false if text.blank?

    normalized = text.downcase.strip
    %w[sí si yes ok vale perfecto está\ bien estabien listo].any? { |word| normalized.include?(word) }
  end

  def negative_response?(text)
    return false if text.blank?

    normalized = text.downcase.strip
    %w[no nop nel nah].any? { |word| normalized == word || normalized.start_with?(word) }
  end

  def done_response?(text)
    return false if text.blank?

    normalized = text.downcase.strip
    %w[listo ya terminé termine eso\ es].any? { |word| normalized.include?(word) }
  end

  def bio_system_prompt
    <<~PROMPT
      Eres un escritor de biografías para trabajadores independientes mexicanos.
      Tu tarea es generar una biografía corta (3-5 oraciones) en español mexicano coloquial y cálido.
      La bio debe ser profesional pero cercana, como si el técnico se presentara en persona.
      NO uses lenguaje corporativo ni formal. Usa un tono natural y directo.
      Responde SOLO con el texto de la biografía, sin comillas ni formato adicional.
      Responde en formato JSON: { "message": "texto de la biografía" }
    PROMPT
  end

  def bio_user_message
    <<~MSG
      Datos del técnico:
      - Nombre: #{data['name']}
      - Oficios: #{(data['categories'] || []).join(', ')}
      - Ciudad: #{data['city']}
      - Zona de servicio: #{data['service_area']}
      - Precio de visita: $#{data['base_price']} MXN
      - Años de experiencia: #{data['years_experience']}
      - Especialidades: #{data['specialties']}
      - Trabajo especializado: #{data['specialized_work']}

      Respuestas personales:
      #{(data['bio_answers'] || []).each_with_index.map { |a, i| "- #{BIO_QUESTIONS[i]}: #{a}" }.join("\n")}
    MSG
  end
end
