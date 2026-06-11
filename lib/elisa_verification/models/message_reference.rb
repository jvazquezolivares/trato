# frozen_string_literal: true

module ElisaVerification
  module Models
    # Value object representing a reference message from v5 spec
    #
    # This class encapsulates a reference message extracted from KIRO_PROMPT_FLOWS_v5.md,
    # including its flow identifier, message text, interpolation variables, and contextual
    # information.
    #
    # @example Creating a simple message reference
    #   MessageReference.new(
    #     flow_id: "P1B",
    #     text: "¡Gracias por contarme! 😊",
    #     interpolation_vars: [],
    #     context: "Decline closing message"
    #   )
    #
    # @example Creating a message with interpolation variables
    #   MessageReference.new(
    #     flow_id: "C5A",
    #     text: "🚨 %{name}, esto suena urgente.",
    #     interpolation_vars: ["name", "provider_name", "phone"],
    #     context: "Alert sent to client when emergency detected"
    #   )
    class MessageReference
      # @return [String] Flow identifier (e.g., "P1B", "C5A")
      attr_reader :flow_id

      # @return [String] The exact message text from v5 specification
      attr_reader :text

      # @return [Array<String>] Variables used in the message (e.g., ["name", "phone"])
      attr_reader :interpolation_vars

      # @return [String] Descriptive context from v5 spec explaining the message purpose
      attr_reader :context

      # Initialize a new MessageReference
      #
      # @param flow_id [String] Flow identifier (e.g., "P1B")
      # @param text [String] The exact message text from v5
      # @param interpolation_vars [Array<String>] Variables used (e.g., ["name", "phone"])
      # @param context [String] Descriptive context from v5 spec
      # @raise [ArgumentError] if flow_id or text is nil or empty
      def initialize(flow_id:, text:, interpolation_vars:, context:)
        raise ArgumentError, "flow_id cannot be nil or empty" if flow_id.nil? || flow_id.empty?
        raise ArgumentError, "text cannot be nil" if text.nil?

        @flow_id = flow_id
        @text = text
        @interpolation_vars = Array(interpolation_vars)
        @context = context || ""

        freeze
      end

      # Check if this message contains interpolation variables
      #
      # @return [Boolean] true if the message has interpolation variables
      def has_interpolation_variables?
        !@interpolation_vars.empty?
      end

      # Get the message text with normalized whitespace
      #
      # @return [String] message text with normalized whitespace
      def normalized_text
        @text.gsub(/\s+/, " ").strip
      end

      # Check equality with another MessageReference
      #
      # @param other [MessageReference] the other message reference to compare
      # @return [Boolean] true if all attributes are equal
      def ==(other)
        return false unless other.is_a?(MessageReference)

        flow_id == other.flow_id &&
          text == other.text &&
          interpolation_vars == other.interpolation_vars &&
          context == other.context
      end

      alias eql? ==

      # Generate hash code for this MessageReference
      #
      # @return [Integer] hash code
      def hash
        [flow_id, text, interpolation_vars, context].hash
      end

      # String representation for debugging
      #
      # @return [String] human-readable representation
      def to_s
        "#<MessageReference flow_id=#{flow_id} vars=#{interpolation_vars.inspect}>"
      end

      # Detailed string representation including message text
      #
      # @return [String] detailed human-readable representation
      def inspect
        "#<MessageReference flow_id=#{flow_id} " \
          "text=#{text[0..50].inspect}#{'...' if text.length > 50} " \
          "vars=#{interpolation_vars.inspect} " \
          "context=#{context[0..30].inspect}#{'...' if context.length > 30}>"
      end
    end
  end
end
