# frozen_string_literal: true

module ElisaAudit
  # Data models for Elisa audit system
  # These structs represent the core data structures used throughout the audit process

  # Represents a single message entry from elisa_es.yml
  # Used by YamlInventoryGenerator to document all messages found in the YAML file
  #
  # @example
  #   MessageEntry.new(
  #     flow_id: 'P1A',
  #     yaml_key: 'elisa.provider.onboarding.welcome',
  #     content: '¡Hola! 👋 Soy Elisa...',
  #     line_number: 42,
  #     variables: ['name', 'ciudad']
  #   )
  MessageEntry = Struct.new(
    :flow_id,        # String: inferred flow ID (e.g., 'P1A', 'C7A')
    :yaml_key,       # String: full YAML key path (e.g., 'elisa.provider.onboarding.welcome')
    :content,        # String: actual message text
    :line_number,    # Integer: line number in elisa_es.yml
    :variables,      # Array<String>: interpolation variables found (e.g., ['name', 'ciudad'])
    keyword_init: true
  ) do
    # Returns true if message contains interpolation variables
    # @return [Boolean]
    def has_variables?
      !!(variables && !variables.empty?)
    end

    # Returns formatted variable list for display
    # @return [String] Comma-separated list of variables or '-' if none
    def formatted_variables
      return '-' unless has_variables?

      variables.map { |v| "%{#{v}}" }.join(', ')
    end
  end

  # Represents an AI usage violation found during audit
  # Used by AiUsageAnalyzer to document mismatches between implementation and AI_Usage_Rules
  #
  # @example
  #   AiUsageViolation.new(
  #     type: :improper_generation,
  #     flow_id: 'P10-P14',
  #     file_path: 'app/services/provider_conversation_handler.rb',
  #     line_number: 156,
  #     method_name: 'send_thank_you_message',
  #     current_impl: 'Using ClaudeService.call to generate thank you message',
  #     expected_impl: 'Must be fixed template from elisa_es.yml',
  #     severity: :critical,
  #     model_used: :haiku
  #   )
  AiUsageViolation = Struct.new(
    :type,           # Symbol: :improper_generation, :missing_extraction, :missing_interpretation
    :flow_id,        # String: flow identifier (e.g., 'P6A', 'C1A')
    :file_path,      # String: path to service file
    :line_number,    # Integer: line number in file
    :method_name,    # String: method where violation occurs
    :current_impl,   # String: description of current implementation
    :expected_impl,  # String: description of correct implementation per AI_Usage_Rules
    :severity,       # Symbol: :critical, :moderate, :minor
    :model_used,     # Symbol: :haiku, :sonnet, or nil
    keyword_init: true
  ) do
    # Returns human-readable severity label
    # @return [String]
    def severity_label
      case severity
      when :critical then '🔴 CRÍTICO'
      when :moderate then '🟡 MODERADO'
      when :minor then '🟢 MENOR'
      else '⚪ DESCONOCIDO'
      end
    end

    # Returns human-readable violation type
    # @return [String]
    def type_label
      case type
      when :improper_generation then 'Generación impropia'
      when :missing_extraction then 'Extracción faltante'
      when :missing_interpretation then 'Interpretación faltante'
      when :wrong_model then 'Modelo incorrecto'
      else 'Tipo desconocido'
      end
    end
  end

  # Represents a WhatsApp Message Template requirement
  # Used by WhatsAppTemplateDetector to identify proactive messages needing Meta approval
  #
  # @example
  #   TemplateRequirement.new(
  #     flow_id: 'P10-P14',
  #     template_name: 'provider_thank_you_review_request',
  #     category: 'UTILITY',
  #     message_text: 'Gracias {{name}}, tu trabajo quedó registrado...',
  #     variables: [{ name: 'name', type: 'text', example: 'Miguel' }],
  #     is_proactive: true,
  #     yaml_key: 'elisa.provider.job_completion.thank_you'
  #   )
  TemplateRequirement = Struct.new(
    :flow_id,        # String: flow identifier (e.g., 'P10-P14', 'C4A')
    :template_name,  # String: suggested template name for Meta registration
    :category,       # String: 'UTILITY' or 'MARKETING'
    :message_text,   # String: exact template text with {{variable}} syntax
    :variables,      # Array<Hash>: [{ name:, type:, example: }]
    :is_proactive,   # Boolean: sent outside 24h window?
    :yaml_key,       # String: corresponding YAML key
    keyword_init: true
  ) do
    # Returns formatted variable list for Meta template registration
    # @return [String] JSON-formatted variable definitions
    def formatted_variables
      return 'Ninguna' if variables.nil? || variables.empty?

      variables.map do |v|
        "#{v[:name]} (#{v[:type]}): ejemplo = '#{v[:example]}'"
      end.join("\n")
    end

    # Returns WhatsApp category badge
    # @return [String]
    def category_badge
      category == 'UTILITY' ? '🔧 UTILITY' : '📢 MARKETING'
    end
  end

  # Represents a manual comparison entry (template for developer to fill during audit)
  # Used by AuditReportGenerator to create comparison template for manual PDF verification
  #
  # @example
  #   ComparisonEntry.new(
  #     flow_id: 'P1A',
  #     yaml_key: 'elisa.provider.onboarding.welcome',
  #     current_text: '¡Hola! 👋 Soy Elisa...',
  #     pdf_text: nil,  # To be filled manually
  #     status: nil,    # To be filled manually
  #     notes: nil      # To be filled manually
  #   )
  ComparisonEntry = Struct.new(
    :flow_id,        # String: flow identifier (e.g., 'P1A', 'C7A')
    :yaml_key,       # String: full YAML key path
    :current_text,   # String: text in elisa_es.yml
    :pdf_text,       # String: text from PDF (filled manually during audit)
    :status,         # Symbol: :exact_match, :mismatch, :missing, :extra (filled manually)
    :notes,          # String: additional context (filled manually)
    keyword_init: true
  ) do
    # Returns status badge for display
    # @return [String]
    def status_badge
      case status
      when :exact_match then '✅ Coincide'
      when :mismatch then '❌ Discrepancia'
      when :missing then '⚠️ Falta en YAML'
      when :extra then '⚠️ Extra en YAML'
      when nil then '⏳ Pendiente'
      else '❓ Desconocido'
      end
    end

    # Returns true if entry requires attention (mismatch, missing, extra)
    # @return [Boolean]
    def requires_attention?
      %i[mismatch missing extra].include?(status)
    end
  end
end
