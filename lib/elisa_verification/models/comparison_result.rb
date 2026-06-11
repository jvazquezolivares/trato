# frozen_string_literal: true

module ElisaVerification
  module Models
    # Value object representing the result of comparing a YAML message against a v5 reference
    #
    # This class encapsulates the comparison outcome, including whether the messages match
    # and any discrepancies found during the comparison.
    #
    # @example Creating a matching result
    #   result = ComparisonResult.new(matches: true, discrepancies: [])
    #   result.matches? # => true
    #
    # @example Creating a result with discrepancies
    #   discrepancy = ComparisonResult::Discrepancy.new(
    #     type: :emoji,
    #     expected: "😊",
    #     actual: "",
    #     description: "Missing emoji after greeting"
    #   )
    #   result = ComparisonResult.new(matches: false, discrepancies: [discrepancy])
    #   result.matches? # => false
    #   result.discrepancies.size # => 1
    class ComparisonResult
      attr_reader :discrepancies

      # Creates a new ComparisonResult
      #
      # @param matches [Boolean] Whether the messages match exactly
      # @param discrepancies [Array<Discrepancy>] List of found discrepancies
      def initialize(matches:, discrepancies:)
        @matches = matches
        @discrepancies = discrepancies.freeze
      end

      # Checks if the messages match exactly
      #
      # @return [Boolean] True if messages match, false otherwise
      def matches?
        @matches
      end

      # Value object representing a specific discrepancy between messages
      #
      # This nested class encapsulates details about a single difference found
      # when comparing a YAML message against its v5 reference.
      #
      # @example Creating an emoji discrepancy
      #   Discrepancy.new(
      #     type: :emoji,
      #     expected: "👋",
      #     actual: "",
      #     description: "Missing wave emoji in greeting"
      #   )
      #
      # @example Creating a wording discrepancy
      #   Discrepancy.new(
      #     type: :wording,
      #     expected: "¡Que te vaya muy bien!",
      #     actual: "¡Que te vaya bien!",
      #     description: "Missing 'muy' intensifier"
      #   )
      class Discrepancy
        attr_reader :type, :expected, :actual, :description

        # Valid discrepancy types
        VALID_TYPES = %i[emoji punctuation wording interpolation].freeze

        # Creates a new Discrepancy
        #
        # @param type [Symbol] Type of discrepancy (:emoji, :punctuation, :wording, :interpolation)
        # @param expected [String] What should be there (from v5 specification)
        # @param actual [String] What is currently there (in YAML)
        # @param description [String] Human-readable description of the discrepancy
        # @raise [ArgumentError] If type is not one of the valid types
        def initialize(type:, expected:, actual:, description:)
          unless VALID_TYPES.include?(type)
            raise ArgumentError, "Invalid discrepancy type: #{type}. Must be one of #{VALID_TYPES.join(', ')}"
          end

          @type = type
          @expected = expected
          @actual = actual
          @description = description
        end

        # Returns a string representation of the discrepancy for debugging
        #
        # @return [String] String representation
        def to_s
          "[#{type}] #{description}: expected '#{expected}', got '#{actual}'"
        end
      end
    end
  end
end
