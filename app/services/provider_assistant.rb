# frozen_string_literal: true

# Handles all provider-facing conversations (Miguel's assistant).
# Manages job registration, work day tracking, task creation,
# financial queries, and social media posting.
#
# Routing: ConversationHandler calls this when the sender's phone
# matches a Provider.phone record.
#
# Flow:
#   1. Find or create Conversation for this provider
#   2. Build system prompt with provider context and history
#   3. Call ClaudeService (haiku for routine, sonnet for creative)
#   4. Execute action from Claude's response
#   5. Send reply via WhatsAppService
#   6. Persist message only when should_save_message is true
class ProviderAssistant
  PROVIDER_SYSTEM_PROMPT = <<~PROMPT
    Eres el asistente de negocios de %{provider_name}, un(a) %{categories} en %{city}.
    Tu trabajo es ayudarle a administrar su negocio de forma conversacional.

    REGLAS DE RESPUESTA:
    - Responde SIEMPRE en JSON válido con estas claves (en inglés), valores en español:
      {
        "message": "texto a enviar al proveedor",
        "action": "none|register_job|register_expense|create_task|update_work_day|financial_query",
        "action_data": {},
        "new_stage": "active|collecting_job_info|collecting_expense_info",
        "updated_context": {},
        "should_save_message": true/false,
        "intent": "job_registered|payment_recorded|expense_registered|task_created|..."
      }

    REGLAS DE PERSISTENCIA:
    - should_save_message = false para mensajes triviales: "ok", "gracias", "perfecto", "listo", "entendido", "si", "no", emojis solos
    - should_save_message = true para intents críticos: job_registered, payment_recorded, expense_registered, appointment_confirmed, appointment_cancelled, complaint_received, provider_unavailable

    REGISTRO DE TRABAJOS (action: "register_job"):
    Cuando %{provider_name} mencione que terminó un trabajo o recibió un pago:
    - Extrae: client_name, client_phone, description, amount, paid_amount, payment_method
    - Si el cliente es conocido y pagó todo: paid_amount = amount
    - Si pagó parcial: paid_amount < amount, pregunta cuándo paga el resto
    - Si no pagó: paid_amount = 0, pregunta si quiere recordatorio de cobro
    - Si no tiene el teléfono del cliente, pregunta por él explicando el beneficio:
      "Con su número puedo mandarle recordatorios y pedirle reseña después 😊 ¿Lo tienes?"
    - El nombre del cliente es obligatorio, el teléfono es opcional pero recomendado

    GASTOS DE MATERIAL (action: "register_expense"):
    Cuando %{provider_name} mencione un gasto de material:
    - Extrae: description, amount, payment_method
    - Pregunta si es para un trabajo específico (job_id) o gasto general
    - Si es general: job_id = null

    action_data para register_job:
    {
      "client_name": "nombre",
      "client_phone": "teléfono o null",
      "description": "descripción del trabajo",
      "amount": "monto total",
      "paid_amount": "monto pagado",
      "payment_method": "cash|transfer",
      "service_date": "YYYY-MM-DD o null"
    }

    action_data para register_expense:
    {
      "description": "descripción del gasto",
      "amount": "monto",
      "payment_method": "cash|transfer",
      "job_id": "id del trabajo o null"
    }

    TONO:
    - Español mexicano coloquial y cálido, siempre respetuoso
    - Máximo 1-2 emojis por mensaje
    - Máximo 5-6 líneas por mensaje
    - Una sola pregunta por mensaje
    - NUNCA regañes a %{provider_name}

    CONTEXTO DEL PROVEEDOR:
    - Clientes registrados: %{client_names}
    - Trabajos recientes: %{recent_jobs}
  PROMPT

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
    response = call_claude(conversation)

    execute_action(response)
    send_reply(response)
    persist_message_if_needed(response, conversation)
    update_conversation(response, conversation)

    response
  end

  private

  # --- Conversation management ---

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

  # --- Claude interaction ---

  def call_claude(conversation)
    ClaudeService.call(
      model: :haiku,
      system_prompt: build_system_prompt,
      user_message: @body,
      context: build_context(conversation)
    )
  end

  def build_system_prompt
    categories = @provider.provider_categories.pluck(:name).join(", ")
    client_names = recent_client_names
    recent_jobs = recent_jobs_summary

    format(
      PROVIDER_SYSTEM_PROMPT,
      provider_name: @provider.name,
      categories: categories.presence || "técnico",
      city: @provider.city || "su ciudad",
      client_names: client_names.presence || "ninguno aún",
      recent_jobs: recent_jobs.presence || "ninguno aún"
    )
  end

  def build_context(conversation)
    context = conversation.context || {}

    # Build history from recent persisted messages
    history = conversation.messages
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

  def recent_client_names
    @provider.clients
             .joins(:provider_clients)
             .where(provider_clients: { provider_id: @provider.id })
             .order("provider_clients.last_contacted_at DESC NULLS LAST")
             .limit(10)
             .pluck(:name)
             .compact
             .join(", ")
  end

  def recent_jobs_summary
    @provider.jobs
             .includes(:client)
             .order(created_at: :desc)
             .limit(5)
             .map { |job| "#{job.client&.name}: #{job.description} ($#{job.amount})" }
             .join("; ")
  end

  # --- Action execution ---

  def execute_action(response)
    action = response["action"]
    action_data = response["action_data"] || {}

    case action
    when "register_job"
      JobRegistrationService.call(
        provider: @provider,
        action: "register_job",
        action_data: action_data
      )
    when "register_expense"
      JobRegistrationService.call(
        provider: @provider,
        action: "register_expense",
        action_data: action_data
      )
    end
  end

  # --- Message handling ---

  def send_reply(response)
    message = response["message"]
    return if message.blank?

    WhatsAppService.send_message(to: @provider.phone, message: message)
  end

  def persist_message_if_needed(response, conversation)
    return unless response["should_save_message"]

    # Persist inbound message
    conversation.messages.create!(
      direction: "inbound",
      body: @body,
      media_url: @media_url,
      intent: response["intent"],
      processed: true
    )

    # Persist outbound reply
    conversation.messages.create!(
      direction: "outbound",
      body: response["message"],
      intent: response["intent"],
      processed: true
    ) if response["message"].present?
  end

  def update_conversation(response, conversation)
    updates = { last_message_at: Time.current }
    updates[:stage] = response["new_stage"] if response["new_stage"].present?
    updates[:context] = response["updated_context"] if response["updated_context"].present?

    conversation.update!(updates)
  end
end
