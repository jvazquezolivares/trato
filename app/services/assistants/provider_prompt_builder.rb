# frozen_string_literal: true

module Assistants
  # Builds system prompts and conversation context for the ProviderAssistant.
  # Assembles provider info, recent clients, and job history into a
  # structured prompt for ClaudeService.
  #
  # Usage:
  #   Assistants::ProviderPromptBuilder.call(provider: provider, conversation: conversation)
  #   # => { system_prompt: "...", context: { "history" => [...] } }
  class ProviderPromptBuilder
    SYSTEM_PROMPT_TEMPLATE = <<~PROMPT
      Eres Elisa, la asistente de negocios de %{provider_name}, un(a) %{categories} en %{city}.
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

    def self.call(provider:, conversation:)
      new(provider: provider, conversation: conversation).build
    end

    def initialize(provider:, conversation:)
      @provider = provider
      @conversation = conversation
    end

    def build
      {
        system_prompt: build_system_prompt,
        context: build_context
      }
    end

    private

    def build_system_prompt
      format(
        SYSTEM_PROMPT_TEMPLATE,
        provider_name: @provider.name,
        categories: provider_categories.presence || "técnico",
        city: @provider.city || "su ciudad",
        client_names: recent_client_names.presence || "ninguno aún",
        recent_jobs: recent_jobs_summary.presence || "ninguno aún"
      )
    end

    def provider_categories
      @provider.provider_categories.pluck(:name).join(", ")
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
