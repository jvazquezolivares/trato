# frozen_string_literal: true

module ElisaAudit
  # Validates YAML syntax for Elisa message files
  #
  # This validator checks for common YAML syntax issues that could cause problems:
  # - Multiline message syntax (proper indentation, quote usage)
  # - Array syntax for List Message options
  # - Interpolation variable syntax (Rails i18n %{var}, not Liquid {{var}})
  # - General YAML structure errors
  #
  # Purpose:
  #   Detect pre-existing syntax errors during Phase 1 audit to document them
  #   before making corrections in Phase 2.
  #
  # Usage:
  #   validator = ElisaAudit::YamlSyntaxValidator.new(yaml_path)
  #   errors = validator.validate
  #
  #   errors.each do |error|
  #     puts "#{error[:line]}: #{error[:message]}"
  #   end
  #
  # Requirements:
  #   - Req 26.1: Parse config/locales/elisa_es.yml to validate YAML syntax
  #   - Req 26.2: Verify multiline messages use proper YAML string syntax
  #   - Req 26.3: Verify arrays (List Message options) are valid YAML arrays
  #   - Req 26.4: Verify interpolation variables use correct Rails i18n syntax
  #   - Req 26.5: Document pre-existing syntax errors in audit report
  class YamlSyntaxValidator
    # Struct to hold validation error details
    ValidationError = Struct.new(
      :line_number,   # Integer: line number where error occurs
      :key_path,      # String: YAML key path (e.g., 'elisa.provider.onboarding.welcome')
      :error_type,    # Symbol: type of error (:multiline, :array, :interpolation, :general)
      :message,       # String: human-readable error description
      :severity,      # Symbol: :critical, :warning, :info
      keyword_init: true
    ) do
      # Returns severity badge for display
      # @return [String]
      def severity_badge
        case severity
        when :critical then '🔴 CRÍTICO'
        when :warning then '🟡 ADVERTENCIA'
        when :info then '🔵 INFO'
        else '⚪ DESCONOCIDO'
        end
      end
    end

    # Initialize validator with YAML file path
    # @param yaml_path [String, Pathname] Path to YAML file
    def initialize(yaml_path)
      @yaml_path = yaml_path
      @errors = []
      @raw_content = nil
      @parsed_content = nil
    end

    # Perform validation and return list of errors
    # @return [Array<ValidationError>] List of validation errors found
    def validate
      @errors = []

      # First, try to parse the YAML to catch syntax errors
      validate_yaml_parseable

      # If parseable, perform detailed validation
      if @parsed_content
        validate_interpolation_syntax
        validate_multiline_syntax
        validate_array_syntax
      end

      @errors
    end

    # Returns true if validation found any errors
    # @return [Boolean]
    def errors?
      @errors.any?
    end

    # Returns count of errors by severity
    # @return [Hash] Counts by severity level
    def error_summary
      {
        critical: @errors.count { |e| e.severity == :critical },
        warning: @errors.count { |e| e.severity == :warning },
        info: @errors.count { |e| e.severity == :info },
        total: @errors.count
      }
    end

    private

    # Validate that YAML file is parseable
    # Catches Psych::SyntaxError and other parsing errors
    def validate_yaml_parseable
      @raw_content = File.read(@yaml_path)
      @parsed_content = YAML.load_file(@yaml_path)
    rescue Psych::SyntaxError => e
      @errors << ValidationError.new(
        line_number: e.line,
        key_path: nil,
        error_type: :general,
        message: "Error de sintaxis YAML: #{e.message}",
        severity: :critical
      )
    rescue Errno::ENOENT
      @errors << ValidationError.new(
        line_number: nil,
        key_path: nil,
        error_type: :general,
        message: "Archivo no encontrado: #{@yaml_path}",
        severity: :critical
      )
    rescue StandardError => e
      @errors << ValidationError.new(
        line_number: nil,
        key_path: nil,
        error_type: :general,
        message: "Error leyendo archivo YAML: #{e.message}",
        severity: :critical
      )
    end

    # Validate interpolation syntax
    # Rails i18n uses %{variable}, not {{variable}} (Liquid/Mustache syntax)
    def validate_interpolation_syntax
      return unless @raw_content

      @raw_content.each_line.with_index(1) do |line, line_number|
        # Skip comments and empty lines
        next if line.strip.empty? || line.strip.start_with?('#')

        # Check for incorrect Liquid/Mustache syntax: {{variable}}
        if line.match?(/\{\{[^}]+\}\}/)
          key_path = extract_key_from_line(line)
          @errors << ValidationError.new(
            line_number: line_number,
            key_path: key_path,
            error_type: :interpolation,
            message: "Sintaxis de interpolación incorrecta: usa %{variable} en lugar de {{variable}} (Rails i18n)",
            severity: :critical
          )
        end

        # Check for potential typos in Rails i18n syntax
        # Look for common mistakes like %{variable without closing brace
        if line.match?(/%\{[^}]*$/) && !line.match?(/\n/)
          key_path = extract_key_from_line(line)
          @errors << ValidationError.new(
            line_number: line_number,
            key_path: key_path,
            error_type: :interpolation,
            message: "Variable de interpolación posiblemente incompleta: falta '}'",
            severity: :warning
          )
        end

        # Check for empty variable names: %{}
        if line.match?(/%\{\s*\}/)
          key_path = extract_key_from_line(line)
          @errors << ValidationError.new(
            line_number: line_number,
            key_path: key_path,
            error_type: :interpolation,
            message: "Variable de interpolación vacía: %{}",
            severity: :critical
          )
        end
      end
    end

    # Validate multiline string syntax
    # YAML supports multiple styles: |, >, |-, >-, quoted strings
    def validate_multiline_syntax
      return unless @raw_content

      @raw_content.each_line.with_index(1) do |line, line_number|
        # Skip comments and empty lines
        next if line.strip.empty? || line.strip.start_with?('#')

        # Check for unquoted strings with special characters that might need quoting
        # This is a heuristic - strings with colons not followed by space might be problematic
        if line.match?(/:\s+[^"'].*:\s/) && !line.match?(/^\s*#/)
          key_path = extract_key_from_line(line)
          @errors << ValidationError.new(
            line_number: line_number,
            key_path: key_path,
            error_type: :multiline,
            message: "Cadena contiene ':' - considera usar comillas para evitar ambigüedad",
            severity: :info
          )
        end

        # Check for strings starting with special YAML indicators
        if line.match?(/:\s+[\[\{\*\&\|\>](?!\s)/)
          key_path = extract_key_from_line(line)
          @errors << ValidationError.new(
            line_number: line_number,
            key_path: key_path,
            error_type: :multiline,
            message: "Cadena comienza con carácter especial YAML - verifica sintaxis",
            severity: :warning
          )
        end
      end
    end

    # Validate array syntax
    # Checks for proper YAML array format in List Message options
    def validate_array_syntax
      return unless @parsed_content

      # Recursively check all arrays in the YAML structure
      validate_arrays_recursive(@parsed_content, 'es')
    end

    # Recursively validate arrays in YAML structure
    # @param node [Hash, Array, String] Current node being validated
    # @param key_path [String] Current key path
    def validate_arrays_recursive(node, key_path)
      case node
      when Hash
        node.each do |key, value|
          new_path = "#{key_path}.#{key}"

          # Special check for List Message structures
          if key == 'list_messages'
            validate_list_message_structure(value, new_path)
          end

          validate_arrays_recursive(value, new_path)
        end
      when Array
        # Validate array entries
        node.each_with_index do |item, index|
          if item.nil?
            @errors << ValidationError.new(
              line_number: nil, # Would need raw content parsing for exact line
              key_path: "#{key_path}[#{index}]",
              error_type: :array,
              message: "Elemento de array vacío o nulo",
              severity: :warning
            )
          elsif item.is_a?(Hash) && item.empty?
            @errors << ValidationError.new(
              line_number: nil,
              key_path: "#{key_path}[#{index}]",
              error_type: :array,
              message: "Elemento de array es hash vacío",
              severity: :warning
            )
          end
        end
      end
    end

    # Validate List Message structure format
    # List Messages must have: title, body, button, options (array)
    # @param list_messages [Hash] List message definitions
    # @param key_path [String] Current key path
    def validate_list_message_structure(list_messages, key_path)
      return unless list_messages.is_a?(Hash)

      list_messages.each do |message_name, structure|
        message_path = "#{key_path}.#{message_name}"

        unless structure.is_a?(Hash)
          @errors << ValidationError.new(
            line_number: nil,
            key_path: message_path,
            error_type: :array,
            message: "List Message debe ser un hash con title, body, button, options",
            severity: :critical
          )
          next
        end

        # Check required fields
        required_fields = %w[title body button options]
        required_fields.each do |field|
          unless structure.key?(field)
            @errors << ValidationError.new(
              line_number: nil,
              key_path: "#{message_path}.#{field}",
              error_type: :array,
              message: "Falta campo requerido '#{field}' en List Message",
              severity: :critical
            )
          end
        end

        # Validate options is an array
        if structure['options']
          if !structure['options'].is_a?(Array)
            @errors << ValidationError.new(
              line_number: nil,
              key_path: "#{message_path}.options",
              error_type: :array,
              message: "Campo 'options' debe ser un array",
              severity: :critical
            )
          elsif structure['options'].empty?
            @errors << ValidationError.new(
              line_number: nil,
              key_path: "#{message_path}.options",
              error_type: :array,
              message: "Array 'options' está vacío - debe tener al menos una opción",
              severity: :critical
            )
          elsif structure['options'].any?(&:nil?)
            @errors << ValidationError.new(
              line_number: nil,
              key_path: "#{message_path}.options",
              error_type: :array,
              message: "Array 'options' contiene elementos nulos",
              severity: :warning
            )
          end
        end
      end
    end

    # Extract key name from a YAML line
    # @param line [String] Line of YAML content
    # @return [String, nil] Extracted key or nil
    def extract_key_from_line(line)
      # Try to extract key before colon
      match = line.match(/^\s*([a-z_]+):/)
      match ? match[1] : nil
    end
  end
end
