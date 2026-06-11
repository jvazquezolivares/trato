# frozen_string_literal: true

module ElisaVerification
  module Models
    # Value object representing the result of YAML validation
    #
    # This class encapsulates validation outcomes, including whether the YAML is valid
    # and any errors encountered during validation (syntax errors, I18n compatibility issues, etc.).
    #
    # @example Creating a valid result
    #   result = ValidationResult.new(valid: true, errors: [])
    #   result.valid? # => true
    #   result.errors # => []
    #
    # @example Creating a result with syntax errors
    #   result = ValidationResult.new(
    #     valid: false,
    #     errors: ["Line 42: mapping values are not allowed here"]
    #   )
    #   result.valid? # => false
    #   result.errors.size # => 1
    #
    # @example Creating a result with I18n compatibility errors
    #   result = ValidationResult.new(
    #     valid: false,
    #     errors: [
    #       "Missing translation key: elisa.provider.onboarding.welcome",
    #       "Invalid interpolation variable: %{unknow_var}"
    #     ]
    #   )
    class ValidationResult
      attr_reader :errors

      # Creates a new ValidationResult
      #
      # @param valid [Boolean] Whether the validation passed
      # @param errors [Array<String>] List of validation errors (empty if valid)
      def initialize(valid:, errors:)
        @valid = valid
        @errors = errors.freeze
      end

      # Checks if the validation passed
      #
      # @return [Boolean] True if validation passed, false otherwise
      def valid?
        @valid
      end

      # Returns a string representation of the validation result for debugging
      #
      # @return [String] String representation
      def to_s
        if valid?
          "ValidationResult: VALID"
        else
          "ValidationResult: INVALID (#{errors.size} error(s))\n" \
            "#{errors.map { |e| "  - #{e}" }.join("\n")}"
        end
      end
    end
  end
end
