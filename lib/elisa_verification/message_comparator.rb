# frozen_string_literal: true

module ElisaVerification
  # Compares YAML messages against v5 reference messages and identifies discrepancies
  #
  # This class is responsible for comparing message text from the YAML file against
  # the official v5 specification reference messages. It normalizes whitespace for
  # comparison while preserving original formatting in the results for corrections.
  #
  # The comparison logic will be expanded in subsequent tasks to detect:
  # - Emoji discrepancies (task 6.2)
  # - Punctuation discrepancies (task 6.3)
  # - Interpolation variable mismatches (task 6.4)
  # - List Message structure differences (task 6.5)
  #
  # @example Basic usage
  #   comparator = MessageComparator.new
  #   reference = MessageReference.new(
  #     flow_id: "P1B",
  #     text: "¡Hola! 👋",
  #     interpolation_vars: [],
  #     context: "Welcome message"
  #   )
  #   result = comparator.compare("¡Hola!    👋", reference)
  #   result.matches? # => true (whitespace normalized)
  #
  # @example With discrepancies
  #   result = comparator.compare("Hola 👋", reference)
  #   result.matches? # => false
  #   result.discrepancies.first.type # => :punctuation
  class MessageComparator
    # Compare a YAML message against a v5 reference message
    #
    # This method performs a comprehensive comparison between a YAML message
    # and its corresponding reference from the v5 specification. It normalizes
    # whitespace for comparison purposes while preserving the original text
    # in any discrepancies for correction purposes.
    #
    # @param yaml_message [String, nil] The message text from YAML
    # @param reference [MessageReference] The reference message from v5 spec
    # @return [ComparisonResult] The result of the comparison
    # @raise [ArgumentError] if reference is nil or not a MessageReference
    #
    # @example Comparing matching messages
    #   result = comparator.compare("¡Hola! 👋", reference)
    #   result.matches? # => true
    #
    # @example Comparing with whitespace differences
    #   result = comparator.compare("¡Hola!    👋", reference)
    #   result.matches? # => true (whitespace is normalized)
    def compare(yaml_message, reference)
      # Validate inputs first - ArgumentErrors should bubble up
      validate_inputs!(yaml_message, reference)

      # Normalize whitespace for both messages
      normalized_yaml = normalize_whitespace(yaml_message)
      normalized_reference = normalize_whitespace(reference.text)

      # If messages match after normalization, return early
      if normalized_yaml == normalized_reference
        return Models::ComparisonResult.new(
          matches: true,
          discrepancies: []
        )
      end

      # Messages don't match - collect all discrepancies from specific comparison helpers
      discrepancies = []

      # Task 6.2: Compare emojis
      emoji_discrepancies = compare_emojis(yaml_message, reference.text)
      discrepancies.concat(emoji_discrepancies)

      # Task 6.3: Compare punctuation
      punctuation_discrepancies = compare_punctuation(yaml_message, reference.text)
      discrepancies.concat(punctuation_discrepancies)

      # Task 6.4: Compare interpolation variables
      interpolation_discrepancies = compare_interpolation_variables(yaml_message, reference)
      discrepancies.concat(interpolation_discrepancies)

      # Task 6.5: Compare List Message structures (if applicable)
      # Note: This handles structured data, not simple strings
      # Implementation will be in a separate method when List Messages are encountered

      # If no specific discrepancies found, flag as general wording issue
      if discrepancies.empty?
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :wording,
          expected: reference.text,
          actual: yaml_message,
          description: "Message text does not match v5 specification"
        )
      end

      Models::ComparisonResult.new(
        matches: false,
        discrepancies: discrepancies
      )
    end

    private

    # Validates the inputs to the compare method
    #
    # @param yaml_message [String, nil] The YAML message to validate
    # @param reference [MessageReference] The reference to validate
    # @raise [ArgumentError] if inputs are invalid
    def validate_inputs!(yaml_message, reference)
      raise ArgumentError, "reference cannot be nil" if reference.nil?

      unless reference.is_a?(Models::MessageReference)
        raise ArgumentError, "reference must be a MessageReference, got #{reference.class}"
      end

      # yaml_message can be nil (missing message), but reference.text cannot
      if reference.text.nil?
        raise ArgumentError, "reference.text cannot be nil"
      end
    end

    # Normalizes whitespace in a message for comparison
    #
    # This method:
    # - Converts nil to empty string
    # - Collapses multiple spaces/tabs into single space
    # - Trims leading and trailing whitespace
    # - Preserves intentional line breaks (\n)
    #
    # The original message text is preserved in the ComparisonResult
    # for correction purposes - we only normalize for comparison.
    #
    # @param message [String, nil] The message to normalize
    # @return [String] The normalized message
    #
    # @example
    #   normalize_whitespace("Hello    world") # => "Hello world"
    #   normalize_whitespace("  Hello  ") # => "Hello"
    #   normalize_whitespace("Hello\n\nWorld") # => "Hello\n\nWorld" (preserves \n)
    def normalize_whitespace(message)
      return "" if message.nil? || message.empty?

      # Normalize whitespace on each line separately to preserve \n
      message.split("\n").map do |line|
        line.gsub(/\s+/, " ").strip
      end.join("\n")
    end

    # Task 6.2: Compare emojis character-by-character
    #
    # Extracts emojis from both messages and compares them.
    # Detects missing or incorrect emojis (e.g., 👋, 🎉, 📋, 🚨).
    #
    # @param yaml_message [String, nil] The message from YAML
    # @param reference_text [String] The reference message from v5 spec
    # @return [Array<Models::ComparisonResult::Discrepancy>] Emoji discrepancies found
    def compare_emojis(yaml_message, reference_text)
      discrepancies = []

      yaml_emojis = extract_emojis(yaml_message || "")
      reference_emojis = extract_emojis(reference_text)

      # Compare emoji lists
      if yaml_emojis != reference_emojis
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :emoji,
          expected: reference_emojis.join(" "),
          actual: yaml_emojis.join(" "),
          description: "Emoji mismatch: expected #{reference_emojis.inspect}, got #{yaml_emojis.inspect}"
        )
      end

      discrepancies
    end

    # Extracts emojis from a message
    #
    # @param message [String] The message to extract emojis from
    # @return [Array<String>] Array of emojis found in the message
    def extract_emojis(message)
      # Unicode emoji regex pattern
      # Matches most common emojis including regional indicators and skin tones
      emoji_pattern = /[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F000}-\u{1F02F}\u{1F0A0}-\u{1F0FF}\u{1F100}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}\u{2300}-\u{23FF}\u{2B50}\u{2B55}\u{203C}\u{2049}\u{25AA}-\u{25AB}\u{25B6}\u{25C0}\u{25FB}-\u{25FE}\u{2934}-\u{2935}\u{2B05}-\u{2B07}\u{2B1B}-\u{2B1C}\u{3030}\u{303D}\u{3297}\u{3299}\u{FE0F}][\u{FE00}-\u{FE0F}]?[\u{200D}]?[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{1F000}-\u{1F02F}\u{1F0A0}-\u{1F0FF}\u{1F100}-\u{1F64F}\u{1F680}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}]?/

      message.scan(emoji_pattern)
    end

    # Task 6.3: Compare punctuation and wording
    #
    # Compares Spanish punctuation marks (¡, !, ¿, ?) and detects wording
    # discrepancies after normalizing interpolation syntax.
    # Handles multiline messages (preserves \n positions).
    #
    # @param yaml_message [String, nil] The message from YAML
    # @param reference_text [String] The reference message from v5 spec
    # @return [Array<Models::ComparisonResult::Discrepancy>] Punctuation discrepancies found
    def compare_punctuation(yaml_message, reference_text)
      discrepancies = []

      yaml_punctuation = extract_punctuation(yaml_message || "")
      reference_punctuation = extract_punctuation(reference_text)

      # Compare punctuation sequences
      if yaml_punctuation != reference_punctuation
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :punctuation,
          expected: reference_punctuation.join(" "),
          actual: yaml_punctuation.join(" "),
          description: "Punctuation mismatch: expected #{reference_punctuation.inspect}, got #{yaml_punctuation.inspect}"
        )
      end

      discrepancies
    end

    # Extracts Spanish punctuation marks from a message
    #
    # @param message [String] The message to extract punctuation from
    # @return [Array<String>] Array of punctuation marks found
    def extract_punctuation(message)
      # Extract Spanish inverted punctuation and common marks
      # Preserves order for position-aware comparison
      message.scan(/[¡!¿?—]/)
    end

    # Task 6.4: Compare interpolation variables
    #
    # Extracts interpolation variables from both messages and compares them.
    # Variables must match exactly. Mismatches are flagged as high-priority errors
    # and should NOT be auto-corrected.
    #
    # Requirement 8.2, 4.5: Flag interpolation mismatches in report, do NOT auto-correct
    #
    # @param yaml_message [String, nil] The message from YAML
    # @param reference [MessageReference] The reference message from v5 spec
    # @return [Array<Models::ComparisonResult::Discrepancy>] Interpolation discrepancies found
    def compare_interpolation_variables(yaml_message, reference)
      discrepancies = []

      yaml_vars = extract_interpolation_variables(yaml_message || "")
      reference_vars = reference.interpolation_vars.sort

      # Compare variable lists (must match exactly)
      if yaml_vars.sort != reference_vars
        # Requirement 8.2: Interpolation variable mismatch flagged as high-priority, NOT auto-corrected
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :interpolation,
          expected: reference_vars.join(", "),
          actual: yaml_vars.join(", "),
          description: "⚠️ HIGH PRIORITY - Interpolation variable mismatch: expected [#{reference_vars.join(', ')}], got [#{yaml_vars.join(', ')}]. DO NOT auto-correct - requires manual review to prevent breaking code."
        )
      end

      discrepancies
    end

    # Extracts interpolation variables from a message
    #
    # Looks for Rails interpolation syntax: %{variable_name}
    #
    # @param message [String] The message to extract variables from
    # @return [Array<String>] Array of variable names found
    def extract_interpolation_variables(message)
      # Extract Rails interpolation variables: %{variable_name}
      message.scan(/%\{(\w+)\}/).flatten
    end

    # Task 6.5: Compare List Message structures
    #
    # Compares title, body, button text, and options arrays for List Messages.
    # Detects array length mismatches and element-by-element differences.
    #
    # Note: This method is designed to handle Hash structures representing List Messages,
    # not simple strings. It should be called when the yaml_message is a Hash.
    #
    # @param yaml_list [Hash] The List Message structure from YAML
    # @param reference_list [Hash] The reference List Message from v5 spec
    # @return [Array<Models::ComparisonResult::Discrepancy>] List Message discrepancies found
    def compare_list_message(yaml_list, reference_list)
      discrepancies = []

      # Compare title
      if yaml_list[:title] != reference_list[:title]
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :wording,
          expected: reference_list[:title],
          actual: yaml_list[:title],
          description: "List Message title mismatch"
        )
      end

      # Compare body
      if yaml_list[:body] != reference_list[:body]
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :wording,
          expected: reference_list[:body],
          actual: yaml_list[:body],
          description: "List Message body mismatch"
        )
      end

      # Compare button
      if yaml_list[:button] != reference_list[:button]
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :wording,
          expected: reference_list[:button],
          actual: yaml_list[:button],
          description: "List Message button text mismatch"
        )
      end

      # Compare options array
      yaml_options = yaml_list[:options] || []
      reference_options = reference_list[:options] || []

      if yaml_options.size != reference_options.size
        discrepancies << Models::ComparisonResult::Discrepancy.new(
          type: :wording,
          expected: "#{reference_options.size} options",
          actual: "#{yaml_options.size} options",
          description: "List Message options array length mismatch"
        )
      else
        # Compare each option element-by-element
        yaml_options.each_with_index do |yaml_option, index|
          reference_option = reference_options[index]
          if yaml_option != reference_option
            discrepancies << Models::ComparisonResult::Discrepancy.new(
              type: :wording,
              expected: reference_option,
              actual: yaml_option,
              description: "List Message option [#{index}] mismatch"
            )
          end
        end
      end

      discrepancies
    end
  end

  # Custom error for comparison failures
  class ComparisonError < StandardError; end
end
