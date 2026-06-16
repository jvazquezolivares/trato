# frozen_string_literal: true

require_relative 'data_models'
require_relative 'errors'

module ElisaAudit
  # Service to validate List Message structures in elisa_es.yml
  #
  # This service verifies that all List Message definitions contain the required fields:
  # - title (string)
  # - body (string)
  # - button (string)
  # - options (array of strings)
  #
  # Purpose:
  #   Extract and validate all List Message structures from YAML configuration,
  #   specifically for flows P1B, P4, and P5 that use WhatsApp List Messages.
  #   Flag any malformed structures that don't meet WhatsApp API requirements.
  #
  # List Message Flows:
  #   - P1B: Decline reasons (provider onboarding)
  #   - P4: Diagnosis visit price range selection
  #   - P5: Years of experience selection
  #   - P17: Financial summary menu (provider financial queries)
  #   - C7A: Star rating collection (client review flow)
  #
  # Usage:
  #   validator = ElisaAudit::ListMessageValidator.new
  #   result = validator.call
  #
  #   # Result is a hash with:
  #   # {
  #   #   list_messages: [ListMessageEntry, ...],
  #   #   malformed: [MalformedListMessage, ...],
  #   #   stats: { total: 5, valid: 4, malformed: 1 }
  #   # }
  #
  # Requirements:
  #   - Req 23.1: Verify P1B decline reasons List Message structure
  #   - Req 23.2: Verify P4 price range List Message structure
  #   - Req 23.3: Verify P5 experience List Message structure
  #   - Req 23.4: Verify all List Message options arrays match PDF
  #   - Req 23.5: Verify titles, bodies, button labels match PDF
  #   - Req 23.6: Save verification to audit report
  class ListMessageValidator
    # YAML file path
    YAML_PATH = Rails.root.join('config', 'locales', 'elisa_es.yml')

    # Expected List Message flows and their YAML paths
    # Maps flow ID to YAML key path for easy lookup
    # Note: Paths include 'es' prefix as it's the root key in the YAML file
    LIST_MESSAGE_FLOWS = {
      'P1B' => 'es.elisa.provider.list_messages.decline_reasons',
      'P4' => 'es.elisa.provider.list_messages.price_range',
      'P5' => 'es.elisa.provider.list_messages.experience',
      'P17' => 'es.elisa.provider.list_messages.financial_summary',
      'C7A' => 'es.elisa.client.list_messages.ratings'
    }.freeze

    # Required fields for a valid List Message structure
    REQUIRED_FIELDS = %w[title body button options].freeze

    def initialize
      @yaml_data = nil
      @list_messages = []
      @malformed = []
    end

    # Main entry point - validates all List Message structures
    #
    # @return [Hash] Result with list_messages, malformed, and stats
    # @raise [YamlParseError] if YAML file cannot be parsed
    def call
      # Load YAML file
      @yaml_data = load_yaml

      # Validate each List Message flow
      LIST_MESSAGE_FLOWS.each do |flow_id, yaml_path|
        validate_list_message(flow_id, yaml_path)
      end

      # Calculate statistics
      stats = {
        total: @list_messages.count + @malformed.count,
        valid: @list_messages.count,
        malformed: @malformed.count
      }

      {
        list_messages: @list_messages,
        malformed: @malformed,
        stats: stats
      }
    end

    private

    # Load and parse YAML file
    # @return [Hash] Parsed YAML data
    # @raise [YamlParseError] if file cannot be loaded or parsed
    def load_yaml
      YAML.load_file(YAML_PATH)
    rescue Psych::SyntaxError => e
      raise YamlParseError, "Invalid YAML syntax at line #{e.line}: #{e.message}"
    rescue Errno::ENOENT
      raise YamlParseError, "File not found: #{YAML_PATH}"
    end

    # Validate a single List Message structure
    # @param flow_id [String] Flow identifier (e.g., 'P1B')
    # @param yaml_path [String] Dot-notation path to List Message in YAML (e.g., 'elisa.provider.list_messages.decline_reasons')
    def validate_list_message(flow_id, yaml_path)
      # Navigate to the List Message data in YAML structure
      list_message_data = navigate_yaml_path(yaml_path)

      if list_message_data.nil?
        # List Message not found in YAML
        @malformed << MalformedListMessage.new(
          flow_id: flow_id,
          yaml_path: yaml_path,
          error: 'List Message not found in YAML',
          missing_fields: REQUIRED_FIELDS
        )
        return
      end

      # Check if it's a hash (required structure)
      unless list_message_data.is_a?(Hash)
        @malformed << MalformedListMessage.new(
          flow_id: flow_id,
          yaml_path: yaml_path,
          error: "List Message must be a hash/object, got #{list_message_data.class}",
          missing_fields: []
        )
        return
      end

      # Validate required fields
      missing_fields = REQUIRED_FIELDS - list_message_data.keys

      if missing_fields.any?
        @malformed << MalformedListMessage.new(
          flow_id: flow_id,
          yaml_path: yaml_path,
          error: "Missing required fields: #{missing_fields.join(', ')}",
          missing_fields: missing_fields
        )
        return
      end

      # Validate options is an array
      unless list_message_data['options'].is_a?(Array)
        @malformed << MalformedListMessage.new(
          flow_id: flow_id,
          yaml_path: yaml_path,
          error: "Options must be an array, got #{list_message_data['options'].class}",
          missing_fields: []
        )
        return
      end

      # Validate options array is not empty
      if list_message_data['options'].empty?
        @malformed << MalformedListMessage.new(
          flow_id: flow_id,
          yaml_path: yaml_path,
          error: 'Options array is empty (must contain at least one option)',
          missing_fields: []
        )
        return
      end

      # Valid List Message - create entry
      @list_messages << ListMessageEntry.new(
        flow_id: flow_id,
        yaml_path: yaml_path,
        title: list_message_data['title'],
        body: list_message_data['body'],
        button: list_message_data['button'],
        options: list_message_data['options'],
        options_count: list_message_data['options'].count
      )
    end

    # Navigate through nested YAML structure using dot-notation path
    # @param path [String] Dot-notation path (e.g., 'elisa.provider.list_messages.decline_reasons')
    # @return [Object, nil] Value at the path, or nil if path doesn't exist
    def navigate_yaml_path(path)
      keys = path.split('.')
      current = @yaml_data

      keys.each do |key|
        return nil unless current.is_a?(Hash)
        return nil unless current.key?(key)

        current = current[key]
      end

      current
    end
  end

  # Data structure for a valid List Message entry
  ListMessageEntry = Struct.new(
    :flow_id,        # String: P1B, P4, P5, etc.
    :yaml_path,      # String: elisa.provider.list_messages.decline_reasons
    :title,          # String: List Message title
    :body,           # String: List Message body text
    :button,         # String: Button label
    :options,        # Array<String>: List of option texts
    :options_count,  # Integer: Number of options
    keyword_init: true
  ) do
    # Format options list for display
    # @return [String] Formatted options list
    def formatted_options
      options.map.with_index(1) { |opt, i| "#{i}. #{opt}" }.join("\n")
    end
  end

  # Data structure for a malformed List Message
  MalformedListMessage = Struct.new(
    :flow_id,         # String: P1B, P4, P5, etc.
    :yaml_path,       # String: elisa.provider.list_messages.decline_reasons
    :error,           # String: Description of what's wrong
    :missing_fields,  # Array<String>: List of missing required fields
    keyword_init: true
  )
end
