# frozen_string_literal: true

module ElisaAudit
  # Configuration module defining AI usage rules and expectations for all Elisa flows
  # Based on prompt-kiro-correccion-copys-ia.md
  #
  # This module serves as the source of truth for:
  # - Which flows should use AI (generation, extraction, interpretation)
  # - Which flows must be fixed templates (never AI-generated)
  # - Which proactive messages require WhatsApp Message Templates
  #
  # Usage:
  #   ElisaAudit::AiUsageRules.expected_for_flow('P6A')
  #   ElisaAudit::AiUsageRules.proactive?('P16')
  module AiUsageRules
    # Flow classifications and AI usage expectations
    # Type categories:
    #   :fixed_template - No AI, message is 100% static template
    #   :extraction - AI converts free text to structured data (message shown is still fixed)
    #   :generation - AI generates message content shown to user
    #   :interpretation - AI determines conversational branch/routing (message shown is still fixed)
    #   :tagging - AI categorizes photos
    #   :detection_semantic - AI detects semantic meaning (no hardcoded keywords)
    #
    # Status categories:
    #   :correct - Implementation is correct, do not modify
    #   :verify - Requires verification during audit
    #   :implement - Needs to be implemented
    #   :critical_verify - Critical verification needed (e.g., P10-P14 must be fixed template)
    #   :undocumented - Not documented in AI usage rules
    FLOWS = {
      # Provider Flows - Onboarding (P1-P9)
      'P1A' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P1B' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P2A' => { type: :fixed_template, model: nil, status: :verify, note: 'Catálogo de oficios, sin IA' },
      'P2B' => { type: :fixed_template, model: nil, status: :verify, note: 'Catálogo de oficios, sin IA' },
      'P3A' => { type: :fixed_template, model: nil, status: :verify, note: 'Detección de prefijo es lógica, sin IA' },
      'P3B' => { type: :fixed_template, model: nil, status: :verify, note: 'Detección de prefijo es lógica, sin IA' },
      'P3C' => { type: :fixed_template, model: nil, status: :verify, note: 'Detección de prefijo es lógica, sin IA' },
      'P3D' => { type: :fixed_template, model: nil, status: :verify, note: 'Detección de prefijo es lógica, sin IA' },
      'P3E' => { type: :extraction, model: :haiku, status: :correct, note: 'Ya implementado, no modificar',
                 extracts: 'ciudad/zonas from free text' },
      'P4' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P5' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P6A' => { type: :generation, model: :sonnet, status: :correct, note: 'Genera [BIO], mensajes son fijos',
                 generates: '[BIO]' },
      'P6B' => { type: :generation, model: :sonnet, status: :correct, note: 'Genera [BIO_REGENERADA], mensajes son fijos',
                 generates: '[BIO_REGENERADA]' },
      'P6C' => { type: :fixed_template, model: nil, status: :verify, note: 'Miguel dicta literal, sin IA' },
      'P7A' => { type: :tagging, model: :haiku, status: :implement, note: 'Debe tagear/categorizar fotos',
                 tags: 'photo categories (plomería, tubería, instalación eléctrica, etc.)' },
      'P7B' => { type: :tagging, model: :haiku, status: :implement, note: 'Debe tagear/categorizar fotos',
                 tags: 'photo categories (plomería, tubería, instalación eléctrica, etc.)' },
      'P8A' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P8B' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P9A' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P9B' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },

      # Provider Flows - Operations (P10-P20)
      'P10-P14' => { type: :fixed_template, model: nil, status: :critical_verify,
                     note: 'CRÍTICO: mensaje debe ser 100% fijo, NO generado por IA. Ya implementado con extracción.',
                     extracts: 'client info and job data' },
      'P15' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'AI detecta gasto general (no trabajo terminado, no consulta). AI extrae monto/material. Mensajes son fijos.',
                 interprets: 'gasto general detection', extracts: 'monto y material' },
      'P16' => { type: :generation_closing, model: :haiku, status: :verify,
                 note: 'Lista de citas es fija (BD). Saludo es fijo. SOLO el cierre es generado por IA.',
                 generates: 'closing message only (¡Que te vaya muy bien!...)',
                 interprets: 'response to ¿Listo para arrancar?' },
      'P17' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'AI detecta que mensaje es consulta financiera. Mensaje de resumen es fijo con números interpolados.',
                 interprets: 'financial query detection' },
      'P18' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P19' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'P20' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'AI interpreta intención de conectar Facebook. Todos los mensajes son fijos.',
                 interprets: 'Facebook connection intent' },

      # Client Flows - Initial contact and search (C1-C3)
      'C1A' => { type: :interpretation_photos, model: :haiku, status: :verify,
                 note: 'Saludo fijo con nombre/oficio/ciudad. AI analiza categoría del problema para decidir qué mensaje de fotos usar (3 ramas).',
                 interprets: 'problem category for photo offering logic' },
      'C1B' => { type: :fixed_template, model: nil, status: :verify, note: 'Búsqueda por short_uuid, sin IA' },
      'C2A' => { type: :undocumented, model: nil, status: :undocumented,
                 note: 'PENDIENTE: no existe copy en PDF. No inventar - dejar marcado como pendiente.' },
      'C2B' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C2C' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C2D' => { type: :extraction, model: :haiku, status: :correct, note: 'Ya implementado, no modificar',
                 extracts: 'ciudad/zonas from free text' },
      'C2E' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C2F' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C2G' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C3A' => { type: :extraction, model: :haiku, status: :correct, note: 'Ya implementado, no modificar',
                 extracts: 'structured data from client message' },
      'C3B' => { type: :fixed_template, model: nil, status: :verify, note: 'Lógica de filtrado por DB, sin IA' },
      'C3C' => { type: :fixed_template, model: nil, status: :verify, note: 'Lógica de filtrado por DB, sin IA' },
      'C3D' => { type: :fixed_template, model: nil, status: :verify, note: 'Lógica de filtrado por DB, sin IA' },
      'C3E' => { type: :fixed_template, model: nil, status: :verify, note: 'Lógica de filtrado por DB, sin IA' },

      # Client Flows - Appointment management (C4)
      'C4A' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'Todos los mensajes mostrados en PDF son fijos. AI interpreta respuestas libres de Miguel/Mariana.',
                 interprets: 'appointment responses (not just button taps)' },
      'C4B' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'Todos los mensajes mostrados en PDF son fijos. AI interpreta respuestas libres de Miguel/Mariana.',
                 interprets: 'appointment responses (not just button taps)' },
      'C4C' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'Todos los mensajes mostrados en PDF son fijos. AI interpreta respuestas libres de Miguel/Mariana.',
                 interprets: 'appointment responses (not just button taps)' },
      'C4D' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'Todos los mensajes mostrados en PDF son fijos. AI interpreta respuestas libres de Miguel/Mariana.',
                 interprets: 'appointment responses (not just button taps)' },
      'C4E' => { type: :interpretation, model: :haiku, status: :verify,
                 note: 'Todos los mensajes mostrados en PDF son fijos. AI interpreta respuestas libres de Miguel/Mariana.',
                 interprets: 'appointment responses (not just button taps)' },

      # Client Flows - Escalation (C5)
      'C5A' => { type: :detection_semantic, model: :haiku, status: :verify_no_keywords,
                 note: 'Mensaje de salida es fijo. AI evalúa semánticamente peligro inminente. NO usar keywords hardcodeadas.',
                 detects: 'emergency situations (humo, gas, inundación, chispas, riesgo eléctrico)' },
      'C5B' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C5C' => { type: :generation_summary, model: :haiku, status: :verify,
                 note: 'Mensajes a Mariana y Miguel son fijos. Solo [RESUMEN] es generado por IA.',
                 generates: '[RESUMEN] - brief problem summary',
                 interprets: '3+ turnos sin Appointment ni problema resuelto' },

      # Client Flows - Work completion (C6)
      'C6A' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C6B' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C6C' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },
      'C6D' => { type: :fixed_template, model: nil, status: :verify, note: 'Sin IA' },

      # Client Flows - Review request (C7)
      'C7A' => { type: :generation_closing, model: :haiku, status: :verify,
                 note: 'Mensajes de solicitud son fijos. AI interpreta respuesta a "¿Quieres dejar comentario?". Cierre es generado por IA.',
                 generates: 'closing message contextualized to comment presence/absence',
                 interprets: 'client response (genuine comment, no-comment, unrelated problem)' },
      'C7B' => { type: :generation_closing, model: :haiku, status: :verify,
                 note: 'Mensajes de solicitud son fijos. AI interpreta respuesta a "¿Quieres dejar comentario?". Cierre es generado por IA.',
                 generates: 'closing message contextualized to comment presence/absence',
                 interprets: 'client response (genuine comment, no-comment, unrelated problem)' },
      'C7C' => { type: :generation_closing, model: :haiku, status: :verify,
                 note: 'Mensajes de solicitud son fijos. AI interpreta respuesta a "¿Quieres dejar comentario?". Cierre es generado por IA.',
                 generates: 'closing message contextualized to comment presence/absence',
                 interprets: 'client response (genuine comment, no-comment, unrelated problem)' },
      'C7D' => { type: :fixed_template, model: nil, status: :verify,
                 note: 'Sin respuesta en ambos intentos, no se genera ningún mensaje. Sin IA.' }
    }.freeze

    # List of flows that send proactive messages requiring WhatsApp Message Templates
    # These messages are sent outside of 24h session window and must be Meta-approved templates
    PROACTIVE_TEMPLATES = [
      'P10-P14', # Thank you + review request to client
      'P16',     # Morning summary (MorningSummaryJob)
      'C4A',     # Initial appointment notice to Miguel and confirmation to Mariana
      'C4D',     # Appointment reminders (1st, 2nd, 3rd) and conciliatory message to Mariana
      'C4E',     # Cancellation notice to Mariana
      'C7A',     # Review request (ReviewRequestJob)
      'C7C'      # Review request second attempt (ReviewRequestJob)
    ].freeze

    # Returns the expected AI usage configuration for a given flow
    # @param flow_id [String] Flow identifier (e.g., 'P6A', 'C4B', 'P16')
    # @return [Hash] Configuration hash with :type, :model, :status, :note, and optional keys
    def self.expected_for_flow(flow_id)
      FLOWS[flow_id] || { type: :unknown, model: nil, status: :undocumented, note: 'Flow not documented in AI usage rules' }
    end

    # Checks if a flow requires proactive WhatsApp Message Template
    # @param flow_id [String] Flow identifier (e.g., 'P16', 'C4A')
    # @return [Boolean] true if flow sends proactive messages requiring templates
    def self.proactive?(flow_id)
      PROACTIVE_TEMPLATES.include?(flow_id)
    end

    # Returns all flows of a specific type
    # @param type [Symbol] Flow type (:fixed_template, :extraction, :generation, etc.)
    # @return [Array<String>] Array of flow IDs matching the type
    def self.flows_by_type(type)
      FLOWS.select { |_flow_id, config| config[:type] == type }.keys
    end

    # Returns all flows requiring a specific model
    # @param model [Symbol] Model type (:haiku, :sonnet)
    # @return [Array<String>] Array of flow IDs using the model
    def self.flows_by_model(model)
      FLOWS.select { |_flow_id, config| config[:model] == model }.keys
    end

    # Returns all flows with a specific status
    # @param status [Symbol] Status (:correct, :verify, :implement, :critical_verify, :undocumented)
    # @return [Array<String>] Array of flow IDs with the status
    def self.flows_by_status(status)
      FLOWS.select { |_flow_id, config| config[:status] == status }.keys
    end
  end
end
