# frozen_string_literal: true

require "yaml"
require "open3"

module ElisaVerification
  # Validator for YAML files with syntax, I18n, and interpolation checks
  #
  # This class validates corrected YAML files to ensure they are:
  # 1. Syntactically valid (can be parsed by Ruby's YAML library)
  # 2. Compatible with Rails I18n (can be loaded by Rails)
  # 3. Using correct interpolation variable syntax (%{var})
  #
  # @example Basic usage
  #   validator = YamlValidator.new('/path/to/elisa_es.yml')
  #   result = validator.validate_all
  #   if result.valid?
  #     puts "YAML file is valid!"
  #   else
  #     puts "Errors found:"
  #     result.errors.each { |error| puts "  - #{error}" }
  #   end
  #
  # @example Validating only syntax
  #   result = validator.validate_syntax
  #   puts result.valid? ? "Syntax OK" : "Syntax errors: #{result.errors}"
  class YamlValidator
    # @return [String] Path to the YAML file being validated
    attr_reader :yaml_file_path

    # Initialize the validator with a YAML file path
    #
    # @param yaml_file_path [String] Path to YAML file to validate
    # @raise [ArgumentError] if yaml_file_path is nil or empty
    # @raise [Errno::ENOENT] if the file does not exist
    def initialize(yaml_file_path)
      raise ArgumentError, "yaml_file_path cannot be nil or empty" if yaml_file_path.nil? || yaml_file_path.empty?
      raise Errno::ENOENT, "File not found: #{yaml_file_path}" unless File.exist?(yaml_file_path)

      @yaml_file_path = yaml_file_path
    end

    # Validate YAML syntax
    #
    # Uses Ruby's YAML.load_file to parse the file and catch any syntax errors.
    # Reports line numbers and error descriptions for any parsing failures.
    #
    # @return [Models::ValidationResult] Validation result with errors array
    def validate_syntax
      errors = []

      begin
        # Attempt to load the YAML file
        YAML.load_file(@yaml_file_path, permitted_classes: [], permitted_symbols: [], aliases: true)
      rescue Psych::SyntaxError => e
        # YAML parsing error - extract line number and message
        error_message = "Line #{e.line}: #{e.problem}"
        error_message += " (#{e.context})" if e.context
        errors << error_message
      rescue StandardError => e
        # Other parsing errors
        errors << "YAML parsing error: #{e.message}"
      end

      Models::ValidationResult.new(valid: errors.empty?, errors: errors)
    end

    # Validate against Rails I18n
    #
    # Executes `rails runner "I18n.backend.load_translations"` to validate that
    # Rails can load the translations without errors. Captures output and detects
    # loading errors and duplicate keys.
    #
    # @return [Models::ValidationResult] Validation result with errors array
    def validate_i18n
      errors = []

      # Build the rails runner command to load translations
      rails_root = File.expand_path("../../..", @yaml_file_path)
      command = "cd #{rails_root} && rails runner \"I18n.backend.load_translations\""

      begin
        stdout, stderr, status = Open3.capture3(command)

        # Check if command executed successfully
        unless status.success?
          errors << "Rails I18n validation failed: #{stderr.strip}" unless stderr.strip.empty?
          errors << "Rails I18n validation failed with exit code #{status.exitstatus}" if errors.empty?
        end

        # Check for common I18n loading errors in output
        combined_output = "#{stdout}\n#{stderr}"

        if combined_output.include?("YAML syntax error")
          errors << "I18n detected YAML syntax error in file"
        end

        if combined_output.include?("duplicate key")
          errors << "I18n detected duplicate keys in YAML"
        end

        if combined_output.include?("translation missing")
          errors << "I18n detected missing translation keys"
        end

        if combined_output =~ /key.*already.*exist/i
          errors << "I18n detected conflicting key definitions"
        end
      rescue StandardError => e
        errors << "Failed to run Rails I18n validation: #{e.message}"
      end

      Models::ValidationResult.new(valid: errors.empty?, errors: errors)
    end

    # Validate interpolation syntax
    #
    # Verifies all interpolation variables use Rails syntax (%{var}).
    # Detects malformed variables and unescaped special characters.
    #
    # @return [Models::ValidationResult] Validation result with errors array
    def validate_interpolation
      errors = []

      begin
        content = File.read(@yaml_file_path, encoding: "UTF-8")

        # Pattern for detecting non-Rails interpolation syntax
        # Common incorrect patterns:
        # - {{var}} (Mustache/Handlebars style)
        # - ${var} (JavaScript/shell style)
        # - %s, %d (printf style)
        # - {var} (Python style)
        # - [var] (Markdown style)

        line_number = 0
        content.each_line do |line|
          line_number += 1

          # Skip comment lines
          next if line.strip.start_with?("#")

          # Detect Mustache/Handlebars style: {{var}}
          if line =~ /\{\{([^}]+)\}\}/
            variable = Regexp.last_match(1)
            errors << "Line #{line_number}: Mustache-style interpolation {{#{variable}}} should be %{#{variable}}"
          end

          # Detect JavaScript/shell style: ${var}
          if line =~ /\$\{([^}]+)\}/
            variable = Regexp.last_match(1)
            errors << "Line #{line_number}: JavaScript-style interpolation ${#{variable}} should be %{#{variable}}"
          end

          # Detect printf style: %s, %d, etc. (but not %{var})
          if line =~ /%([sd]|[0-9]+)(?![{])/
            errors << "Line #{line_number}: Printf-style interpolation (#{Regexp.last_match(0)}) should use named variables %{var}"
          end

          # Detect Python/simple style: {var} (but not %{var})
          if line =~ /(?<!%)\{([a-z_][a-z0-9_]*)\}/i
            variable = Regexp.last_match(1)
            errors << "Line #{line_number}: Python-style interpolation {#{variable}} should be %{#{variable}}"
          end

          # Detect malformed Rails interpolation: %{var with spaces} or %{var-with-dashes}
          if line =~ /%\{([^}]+)\}/
            variable = Regexp.last_match(1)

            # Check for spaces in variable names
            if variable.include?(" ")
              errors << "Line #{line_number}: Interpolation variable %{#{variable}} contains spaces - use underscores"
            end

            # Check for dashes instead of underscores
            if variable.include?("-")
              errors << "Line #{line_number}: Interpolation variable %{#{variable}} contains dashes - use underscores"
            end

            # Check for invalid characters (only letters, numbers, underscores allowed)
            unless variable =~ /^[a-z_][a-z0-9_]*$/i
              errors << "Line #{line_number}: Interpolation variable %{#{variable}} contains invalid characters"
            end
          end

          # Detect unescaped percent signs that might be intended as interpolation
          # Match % followed by a letter (but not {, %, or whitespace)
          # This catches cases like "%off" or "%discount" that should likely be "%%off"
          if line =~ /%(?![{%\s])(?=[a-zA-Z])/
            errors << "Line #{line_number}: Unescaped % character detected - use %% to escape or %{var} for interpolation"
          end
        end
      rescue StandardError => e
        errors << "Failed to validate interpolation syntax: #{e.message}"
      end

      Models::ValidationResult.new(valid: errors.empty?, errors: errors)
    end

    # Run all validations
    #
    # Executes syntax validation, interpolation validation, and I18n validation.
    # Returns a combined result with all errors found.
    #
    # @return [Models::ValidationResult] Combined validation result
    def validate_all
      all_errors = []

      # Run syntax validation first - if syntax is invalid, other validations will fail
      syntax_result = validate_syntax
      return syntax_result unless syntax_result.valid?

      # Run interpolation validation
      interpolation_result = validate_interpolation
      all_errors.concat(interpolation_result.errors)

      # Run I18n validation
      i18n_result = validate_i18n
      all_errors.concat(i18n_result.errors)

      Models::ValidationResult.new(valid: all_errors.empty?, errors: all_errors)
    end
  end
end
