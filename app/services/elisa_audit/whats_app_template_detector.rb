# frozen_string_literal: true

require_relative 'data_models'
require_relative 'ai_usage_rules'
require_relative 'errors'

module ElisaAudit
  # Service to identify all proactive WhatsApp messages requiring Meta-approved Message Templates
  #
  # This service analyzes flows that send messages outside the 24-hour customer service window,
  # which require pre-approved WhatsApp Message Templates per Meta's Business API policies.
  #
  # Purpose:
  #   Identify all proactive messages, extract their content from elisa_es.yml, detect variables,
  #   classify template category (UTILITY/MARKETING), and format requirements for Meta registration.
  #
  # Proactive Flows:
  #   - P10-P14: Thank you + review request after job completion
  #   - P16: Morning summary with pending tasks
  #   - C4A: Initial appointment notice to provider and confirmation to client
  #   - C4D: Appointment reminders (1st, 2nd, 3rd) and conciliatory message
  #   - C4E: Appointment cancellation notice
  #   - C7A: Review request to client
  #   - C7C: Review request second attempt
  #
  # Usage:
  #   detector = ElisaAudit::WhatsAppTemplateDetector.new
  #   requirements = detector.call
  #
  #   # Returns array of TemplateRequirement structs
  #   requirements.each do |req|
  #     puts "#{req.flow_id}: #{req.template_name} (#{req.category})"
  #     puts "Variables: #{req.variables.map { |v| v[:name] }.join(', ')}"
  #   end
  #
  # Requirements:
  #   - Req 4.1-4.7: Identify missing WhatsApp Message Templates
  #   - Req 18.1-18.6: Document all template variables for Meta approval
  class WhatsAppTemplateDetector
    # Flows that send proactive messages requiring WhatsApp Message Templates
    # These messages are sent outside the 24-hour customer service window
    PROACTIVE_FLOWS = %w[P10-P14 P16 C4A C4D C4E C7A C7C].freeze

    # Path to the elisa_es.yml file
    YAML_PATH = Rails.root.join('config', 'locales', 'elisa_es.yml')

    # Initialize the detector
    def initialize
      @yaml_content = nil
      @requirements = []
    end

    # Main entry point - detects all template requirements
    # @return [Array<TemplateRequirement>] List of template requirements for Meta registration
    # @raise [YamlParseError] if YAML file cannot be parsed
    def call
      load_yaml
      detect_all_templates
      @requirements
    end

    private

    # Load and parse the YAML file
    # @raise [YamlParseError] if file cannot be loaded
    def load_yaml
      unless File.exist?(YAML_PATH)
        raise YamlParseError, "File not found: #{YAML_PATH}"
      end

      @yaml_content = YAML.load_file(YAML_PATH)
    rescue Psych::SyntaxError => e
      raise YamlParseError, "Invalid YAML syntax at line #{e.line}: #{e.message}"
    rescue StandardError => e
      raise YamlParseError, "Error reading YAML file: #{e.message}"
    end

    # Detect template requirements for all proactive flows
    def detect_all_templates
      PROACTIVE_FLOWS.each do |flow_id|
        requirements = detect_template_for_flow(flow_id)
        @requirements.concat(requirements) if requirements
      end
    end

    # Detect template requirement(s) for a specific flow
    # @param flow_id [String] Flow identifier (e.g., 'P10-P14', 'C4A')
    # @return [Array<TemplateRequirement>, nil] Template requirement(s) or nil if not found
    def detect_template_for_flow(flow_id)
      case flow_id
      when 'P10-P14'
        detect_p10_p14_template
      when 'P16'
        detect_p16_template
      when 'C4A'
        detect_c4a_templates
      when 'C4D'
        detect_c4d_templates
      when 'C4E'
        detect_c4e_template
      when 'C7A'
        detect_c7a_template
      when 'C7C'
        detect_c7c_template
      else
        Rails.logger.warn("Unknown proactive flow: #{flow_id}")
        nil
      end
    end

    # P10-P14: Thank you + review request after job completion
    # This is sent proactively after provider confirms job completion
    def detect_p10_p14_template
      # The thank you message is sent to the CLIENT, not provider
      # Based on the design, this message should exist in client flows
      # However, the current YAML doesn't have this message explicitly
      # We need to infer or document this as missing

      # Template structure based on requirements document section 4.2 and 7.1
      message_text = "Gracias {{nombre_proveedor}}, tu trabajo con {{nombre_cliente}} quedó registrado. " \
                     "¿Nos ayudarías dejando una reseña? Es importante para conseguir más clientes."

      variables = [
        { name: 'nombre_proveedor', type: 'text', example: 'Miguel' },
        { name: 'nombre_cliente', type: 'text', example: 'María' }
      ]

      [
        TemplateRequirement.new(
          flow_id: 'P10-P14',
          template_name: 'provider_thank_you_review_request',
          category: 'UTILITY',
          message_text: message_text,
          variables: variables,
          is_proactive: true,
          yaml_key: 'elisa.provider.completion.thank_you (MISSING - needs to be created)'
        )
      ]
    end

    # P16: Morning summary with pending tasks
    # This is sent daily via MorningSummaryJob
    def detect_p16_template
      # Extract morning summary messages from YAML
      morning_summary = dig_yaml('es', 'elisa', 'provider', 'morning_summary')

      return nil unless morning_summary

      # The morning summary has two variants: with tasks and without tasks
      # For WhatsApp templates, we need both variants

      with_tasks_header = morning_summary['with_tasks_header'] || ''
      with_tasks_footer = morning_summary['with_tasks_footer'] || ''
      no_tasks = morning_summary['no_tasks'] || ''

      # Template 1: Morning summary WITH pending tasks
      with_tasks_text = convert_to_template_syntax(with_tasks_header) + "\n" \
                        "{{lista_tareas}}\n\n" \
                        + with_tasks_footer

      with_tasks_variables = extract_variables_from_message(with_tasks_header)
      with_tasks_variables << { name: 'lista_tareas', type: 'text', example: "1. Llamar al señor Pérez\n2. Comprar cable" }

      # Template 2: Morning summary WITHOUT pending tasks
      no_tasks_text = convert_to_template_syntax(no_tasks)
      no_tasks_variables = extract_variables_from_message(no_tasks)

      [
        TemplateRequirement.new(
          flow_id: 'P16',
          template_name: 'provider_morning_summary_with_tasks',
          category: 'UTILITY',
          message_text: with_tasks_text,
          variables: with_tasks_variables,
          is_proactive: true,
          yaml_key: 'es.elisa.provider.morning_summary.with_tasks_header'
        ),
        TemplateRequirement.new(
          flow_id: 'P16',
          template_name: 'provider_morning_summary_no_tasks',
          category: 'UTILITY',
          message_text: no_tasks_text,
          variables: no_tasks_variables,
          is_proactive: true,
          yaml_key: 'es.elisa.provider.morning_summary.no_tasks'
        )
      ]
    end

    # C4A: Initial appointment notice to provider and confirmation to client
    # Two separate messages are sent proactively
    def detect_c4a_templates
      appointment = dig_yaml('es', 'elisa', 'client', 'appointment')

      return nil unless appointment

      notification_header = appointment['notification_header'] || ''
      notification_footer = appointment['notification_footer'] || ''

      # Template 1: Appointment notification to PROVIDER (Miguel)
      provider_message = notification_header + "\n\n" \
                         "👤 Cliente: {{nombre_cliente}}\n" \
                         "📱 Teléfono: {{telefono_cliente}}\n" \
                         "🔧 Servicio: {{tipo_servicio}}\n" \
                         "📍 Dirección: {{direccion}}\n" \
                         "📅 Fecha: {{fecha}}\n" \
                         "⏱ Duración estimada: {{duracion}}\n\n" \
                         + notification_footer

      provider_variables = [
        { name: 'nombre_cliente', type: 'text', example: 'María López' },
        { name: 'telefono_cliente', type: 'text', example: '+52 229 123 4567' },
        { name: 'tipo_servicio', type: 'text', example: 'Reparación de tubería' },
        { name: 'direccion', type: 'text', example: 'Av. Principal 123, Col. Centro' },
        { name: 'fecha', type: 'text', example: 'Mañana 10:00 AM' },
        { name: 'duracion', type: 'text', example: '1-2 horas' }
      ]

      # Template 2: Appointment confirmation to CLIENT (Mariana)
      client_message = "¡Listo! Tu cita con {{nombre_proveedor}} quedó agendada para {{fecha}}. " \
                       "Te confirmo cuando el técnico esté en camino. 😊"

      client_variables = [
        { name: 'nombre_proveedor', type: 'text', example: 'Miguel' },
        { name: 'fecha', type: 'text', example: 'mañana a las 10:00 AM' }
      ]

      [
        TemplateRequirement.new(
          flow_id: 'C4A',
          template_name: 'appointment_notification_to_provider',
          category: 'UTILITY',
          message_text: provider_message,
          variables: provider_variables,
          is_proactive: true,
          yaml_key: 'es.elisa.client.appointment.notification_header'
        ),
        TemplateRequirement.new(
          flow_id: 'C4A',
          template_name: 'appointment_confirmation_to_client',
          category: 'UTILITY',
          message_text: client_message,
          variables: client_variables,
          is_proactive: true,
          yaml_key: 'es.elisa.client.appointment.confirmation (MISSING - needs to be created)'
        )
      ]
    end

    # C4D: Appointment reminders and conciliatory message
    # Multiple reminder messages sent at different intervals
    def detect_c4d_templates
      # These messages are not in the current YAML
      # Need to document as missing

      # Template 1: First reminder (1 hour before)
      reminder_1h = "Hola {{nombre_proveedor}} 👋 Te recuerdo que tienes cita con {{nombre_cliente}} " \
                    "en 1 hora ({{hora_cita}}). 📅"

      # Template 2: Second reminder (at appointment time)
      reminder_now = "{{nombre_proveedor}}, tu cita con {{nombre_cliente}} es AHORA. " \
                     "Dirección: {{direccion}}. ¿Ya saliste?"

      # Template 3: Third reminder (client waiting)
      reminder_waiting = "{{nombre_proveedor}}, {{nombre_cliente}} está esperando. " \
                         "Por favor avísale si vas retrasado."

      # Template 4: Conciliatory message to client
      conciliatory = "Hola {{nombre_cliente}}, disculpa la espera. Le recordé a {{nombre_proveedor}} " \
                     "tu cita. ¿Prefieres reagendar para otro día?"

      common_variables = [
        { name: 'nombre_proveedor', type: 'text', example: 'Miguel' },
        { name: 'nombre_cliente', type: 'text', example: 'María' }
      ]

      [
        TemplateRequirement.new(
          flow_id: 'C4D',
          template_name: 'appointment_reminder_1h',
          category: 'UTILITY',
          message_text: reminder_1h,
          variables: common_variables + [
            { name: 'hora_cita', type: 'text', example: '10:00 AM' }
          ],
          is_proactive: true,
          yaml_key: 'es.elisa.client.appointment.reminder_1h (MISSING - needs to be created)'
        ),
        TemplateRequirement.new(
          flow_id: 'C4D',
          template_name: 'appointment_reminder_now',
          category: 'UTILITY',
          message_text: reminder_now,
          variables: common_variables + [
            { name: 'direccion', type: 'text', example: 'Av. Principal 123' }
          ],
          is_proactive: true,
          yaml_key: 'es.elisa.client.appointment.reminder_now (MISSING - needs to be created)'
        ),
        TemplateRequirement.new(
          flow_id: 'C4D',
          template_name: 'appointment_reminder_waiting',
          category: 'UTILITY',
          message_text: reminder_waiting,
          variables: common_variables,
          is_proactive: true,
          yaml_key: 'es.elisa.client.appointment.reminder_waiting (MISSING - needs to be created)'
        ),
        TemplateRequirement.new(
          flow_id: 'C4D',
          template_name: 'appointment_conciliatory_to_client',
          category: 'UTILITY',
          message_text: conciliatory,
          variables: common_variables,
          is_proactive: true,
          yaml_key: 'es.elisa.client.appointment.conciliatory (MISSING - needs to be created)'
        )
      ]
    end

    # C4E: Appointment cancellation notice
    def detect_c4e_template
      # Cancellation message to client when provider cancels
      cancellation_message = "Hola {{nombre_cliente}}, {{nombre_proveedor}} no podrá asistir a tu cita " \
                             "de {{fecha}}. ¿Quieres que te ayude a reagendar con otro horario?"

      variables = [
        { name: 'nombre_cliente', type: 'text', example: 'María' },
        { name: 'nombre_proveedor', type: 'text', example: 'Miguel' },
        { name: 'fecha', type: 'text', example: 'mañana a las 10:00 AM' }
      ]

      [
        TemplateRequirement.new(
          flow_id: 'C4E',
          template_name: 'appointment_cancellation_notice',
          category: 'UTILITY',
          message_text: cancellation_message,
          variables: variables,
          is_proactive: true,
          yaml_key: 'es.elisa.client.appointment.cancellation (MISSING - needs to be created)'
        )
      ]
    end

    # C7A: Review request to client (first attempt)
    def detect_c7a_template
      review = dig_yaml('es', 'elisa', 'client', 'review')

      return nil unless review

      # Initial review request message
      request_message = "Hola {{nombre_cliente}} 👋 ¿Cómo te fue con {{nombre_proveedor}}? " \
                        "Me ayudarías mucho calificando el trabajo del 1 al 5. ⭐"

      variables = [
        { name: 'nombre_cliente', type: 'text', example: 'María' },
        { name: 'nombre_proveedor', type: 'text', example: 'Miguel' }
      ]

      [
        TemplateRequirement.new(
          flow_id: 'C7A',
          template_name: 'review_request_first_attempt',
          category: 'UTILITY',
          message_text: request_message,
          variables: variables,
          is_proactive: true,
          yaml_key: 'es.elisa.client.review.request (MISSING - needs to be created)'
        )
      ]
    end

    # C7C: Review request second attempt
    def detect_c7c_template
      # Second attempt review request (sent if first attempt gets no response)
      request_message = "Hola {{nombre_cliente}}, soy Elisa de Trato. ¿Tuviste tiempo de calificar " \
                        "el trabajo de {{nombre_proveedor}}? Tu opinión es muy valiosa. ⭐"

      variables = [
        { name: 'nombre_cliente', type: 'text', example: 'María' },
        { name: 'nombre_proveedor', type: 'text', example: 'Miguel' }
      ]

      [
        TemplateRequirement.new(
          flow_id: 'C7C',
          template_name: 'review_request_second_attempt',
          category: 'UTILITY',
          message_text: request_message,
          variables: variables,
          is_proactive: true,
          yaml_key: 'es.elisa.client.review.request_retry (MISSING - needs to be created)'
        )
      ]
    end

    # Extract variables from a message and convert to template format
    # @param message [String] Message text with Rails i18n interpolation (%{var})
    # @return [Array<Hash>] Array of variable definitions with name, type, and example
    def extract_variables_from_message(message)
      return [] if message.nil? || message.empty?

      # Match Rails i18n interpolation syntax: %{variable_name}
      variable_names = message.scan(/%\{([^}]+)\}/).flatten.uniq

      variable_names.map do |var_name|
        {
          name: var_name,
          type: 'text',
          example: generate_example_for_variable(var_name)
        }
      end
    end

    # Generate example value for a variable based on its name
    # @param var_name [String] Variable name
    # @return [String] Example value
    def generate_example_for_variable(var_name)
      case var_name
      when 'name', 'nombre_proveedor', 'provider_name'
        'Miguel'
      when 'nombre_cliente', 'client_name'
        'María'
      when 'count'
        '3'
      when 'tasks_word'
        'pendientes'
      when 'ciudad', 'city'
        'Veracruz'
      when 'fecha', 'date'
        'mañana a las 10:00 AM'
      when 'phone', 'telefono'
        '+52 229 123 4567'
      when 'state'
        'Veracruz'
      when 'rating'
        '5'
      when 'keyword'
        'humo'
      else
        "{{#{var_name}}}"
      end
    end

    # Convert Rails i18n interpolation syntax to WhatsApp template syntax
    # Converts %{variable} to {{variable}}
    # @param message [String] Message with Rails syntax
    # @return [String] Message with WhatsApp template syntax
    def convert_to_template_syntax(message)
      return '' if message.nil?

      message.gsub(/%\{([^}]+)\}/, '{{\1}}')
    end

    # Safely dig into nested YAML structure
    # @param keys [Array<String>] Nested keys to traverse
    # @return [Hash, String, nil] Value at the nested key path
    def dig_yaml(*keys)
      keys.reduce(@yaml_content) do |hash, key|
        return nil unless hash.is_a?(Hash)

        hash[key]
      end
    end
  end
end
