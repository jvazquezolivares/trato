# frozen_string_literal: true

module ElisaVerification
  module Models
    # Value object for tracking a message comparison between YAML and v5 specification
    #
    # This class encapsulates the result of comparing a message from elisa_es.yml
    # against its reference in KIRO_PROMPT_FLOWS_v5.md.
    #
    # @example
    #   comparison = MessageComparison.new(
    #     key: "elisa.provider.onboarding.welcome",
    #     flow_id: "P1A",
    #     yaml_value: "¡Hola! 👋 Soy Elisa...",
    #     reference_value: "¡Hola! 👋 Soy Elisa...",
    #     comparison_result: ComparisonResult.new(matches: true, discrepancies: []),
    #     corrected: false
    #   )
    #
    #   comparison.matched? #=> true
    #   comparison.corrected? #=> false
    class MessageComparison
      attr_reader :key, :flow_id, :yaml_value, :reference_value,
                  :comparison_result, :corrected

      # Initialize a new MessageComparison
      #
      # @param key [String] YAML key in dot notation (e.g., "elisa.provider.onboarding.welcome")
      # @param flow_id [String] Flow ID from v5 spec (e.g., "P1A", "C5A")
      # @param yaml_value [String] Original message text from YAML file
      # @param reference_value [String] Reference message text from v5 specification
      # @param comparison_result [ComparisonResult] Result of comparing the two values
      # @param corrected [Boolean] Whether a correction was applied to this message
      def initialize(key:, flow_id:, yaml_value:, reference_value:, comparison_result:, corrected:)
        @key = key
        @flow_id = flow_id
        @yaml_value = yaml_value
        @reference_value = reference_value
        @comparison_result = comparison_result
        @corrected = corrected
      end

      # Check if the message matched the v5 specification
      #
      # A message is considered matched if the comparison result indicates
      # that the YAML value and reference value are identical (no discrepancies).
      #
      # @return [Boolean] true if message matches v5 spec exactly
      def matched?
        comparison_result&.matches? || false
      end

      # Check if a correction was applied to this message
      #
      # This indicates whether the verification system updated the YAML
      # message text to match the v5 specification.
      #
      # @return [Boolean] true if correction was needed and applied
      def corrected?
        corrected == true
      end
    end
  end
end
