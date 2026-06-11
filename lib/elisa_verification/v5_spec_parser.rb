# frozen_string_literal: true

module ElisaVerification
  # Parser for KIRO_PROMPT_FLOWS_v5.md specification document
  #
  # This class extracts reference messages from the v5 specification markdown file,
  # parsing flow IDs, message text, List Message structures, and interpolation variables.
  #
  # @example Basic usage
  #   parser = V5SpecParser.new('/path/to/KIRO_PROMPT_FLOWS_v5.md')
  #   messages = parser.parse
  #   p1b_message = parser.message_for('P1B')
  #
  # @example Accessing parsed messages
  #   messages = parser.parse
  #   messages['P1B'].text  # => "¡Gracias por contarme! 😊..."
  #   messages['C5A'].interpolation_vars  # => ["name", "provider_name", "phone"]
  class V5SpecParser
    # @return [String] Path to the v5 specification file
    attr_reader :spec_file_path

    # @return [Hash<String, MessageReference>] Parsed messages keyed by flow_id
    attr_reader :messages

    # Initialize the parser with a specification file path
    #
    # @param spec_file_path [String] Path to KIRO_PROMPT_FLOWS_v5.md
    # @raise [ArgumentError] if spec_file_path is nil or empty
    # @raise [Errno::ENOENT] if the file does not exist
    def initialize(spec_file_path)
      raise ArgumentError, "spec_file_path cannot be nil or empty" if spec_file_path.nil? || spec_file_path.empty?
      raise Errno::ENOENT, "File not found: #{spec_file_path}" unless File.exist?(spec_file_path)

      @spec_file_path = spec_file_path
      @messages = {}
      @content = nil
    end

    # Parse the specification file and extract all reference messages
    #
    # This method reads the v5 spec markdown, extracts flow IDs from section headers,
    # quoted messages, List Message structures, and interpolation variables.
    #
    # @return [Hash<String, MessageReference>] Mapping of flow_id => MessageReference
    #   Example: { "P1B" => MessageReference, "C5A" => MessageReference }
    def parse
      @content = File.read(@spec_file_path, encoding: "UTF-8")
      @messages = {}

      # Parse all sections with flow IDs in headers
      parse_all_flow_sections

      @messages
    rescue StandardError => e
      # Requirement 8.1: Handle V5 spec parse failures gracefully
      warn "Error parsing v5 specification file #{@spec_file_path}: #{e.message}"
      warn "Continuing with messages extracted so far..."
      @messages
    end

    # Get reference message for a specific flow ID
    #
    # @param flow_id [String] Flow identifier (e.g., "P1B", "C5A")
    # @return [MessageReference, nil] The message reference or nil if not found
    def message_for(flow_id)
      @messages[flow_id]
    end

    private

    # Parse all flow sections from the spec by finding headers with flow IDs
    def parse_all_flow_sections
      # Pattern matches headers like: ### 2.1 — P1B: or ### 3.5 — C5A:
      header_pattern = /^###\s+\d+\.\d+\s+—\s+([A-Z]\d+[A-Z]?):\s*(.+?)$/

      @content.scan(header_pattern).each do |match|
        flow_id = match[0].strip
        section_title = match[1].strip

        # Extract the section content
        section_content = extract_flow_section(flow_id)
        next unless section_content

        # Parse messages from this section with error handling
        # Requirement 8.1: Handle V5 spec parse failures (log error, continue with other messages)
        begin
          parse_section_messages(flow_id, section_title, section_content)
        rescue StandardError => e
          warn "Warning: Failed to parse messages for flow #{flow_id}: #{e.message}"
          warn "Skipping flow #{flow_id} and continuing with other flows..."
        end
      end
    end

    # Extract a flow section from the spec content
    #
    # @param flow_id [String] The flow identifier
    # @return [String, nil] The section content or nil if not found
    def extract_flow_section(flow_id)
      # Pattern to find the section header
      header_pattern = /^###\s+\d+\.\d+\s+—\s+#{Regexp.escape(flow_id)}:\s*.+?$/

      # Find the start of this section
      start_match = @content.match(header_pattern)
      return nil unless start_match

      start_pos = start_match.end(0)

      # Find the end (next ### header or end of file)
      end_pattern = /^###\s+\d+\.\d+\s+—/
      rest_content = @content[start_pos..]
      end_match = rest_content.match(end_pattern)

      if end_match
        # Extract until the next section
        section_end = start_pos + end_match.begin(0)
        @content[start_pos...section_end]
      else
        # Extract until end of file
        @content[start_pos..]
      end
    end

    # Parse messages from a section
    #
    # @param flow_id [String] The flow identifier
    # @param section_title [String] The section title
    # @param content [String] The section content
    def parse_section_messages(flow_id, section_title, content)
      # Try to extract quoted messages (both single line and multiline)
      extract_quoted_messages(flow_id, section_title, content)

      # Try to extract List Messages
      extract_list_messages(flow_id, section_title, content)

      # Try to extract code block messages
      extract_code_block_messages(flow_id, section_title, content)
    end

    # Extract quoted messages from section content
    #
    # @param flow_id [String] The flow identifier
    # @param section_title [String] The section title
    # @param content [String] The section content
    def extract_quoted_messages(flow_id, section_title, content)
      # Pattern for quoted messages: "message text"
      # Handles multiline quotes
      quoted_pattern = /"([^"]+)"/m

      message_counter = 0

      content.scan(quoted_pattern) do |match|
        message_text = match[0].strip
        next if message_text.empty?

        # Skip if this looks like it's just a title or single word
        next if message_text.split.length == 1 && !message_text.match?(/[¡!¿?]/)

        message_counter += 1

        # Determine context from surrounding text
        context = determine_message_context(content, message_text, section_title)

        # Extract and convert interpolation variables
        vars = extract_interpolation_variables(message_text)
        converted_text = convert_to_rails_syntax(message_text)

        # Create unique key for multiple messages in same flow
        key = message_counter == 1 && content.scan(quoted_pattern).length == 1 ? flow_id : "#{flow_id}_msg_#{message_counter}"

        @messages[key] = Models::MessageReference.new(
          flow_id: flow_id,
          text: converted_text,
          interpolation_vars: vars,
          context: context
        )
      end
    end

    # Determine context for a message based on surrounding text
    #
    # @param section_content [String] The section content
    # @param message_text [String] The message text
    # @param section_title [String] The section title
    # @return [String] Context description
    def determine_message_context(section_content, message_text, section_title)
      # Look for context clues before the message
      message_pos = section_content.index(message_text)
      return section_title unless message_pos

      # Get text before the message (up to 200 chars)
      context_start = [message_pos - 200, 0].max
      context_text = section_content[context_start...message_pos]

      # Look for common context patterns
      if context_text =~ /(Elisa|Send to|Provider receives|Client receives):\s*$/i
        Regexp.last_match(1)
      elsif context_text =~ /(\d+\.\s+.+?):\s*$/
        Regexp.last_match(1)
      else
        section_title
      end
    end

    # Extract List Messages from section content
    #
    # @param flow_id [String] The flow identifier
    # @param section_title [String] The section title
    # @param content [String] The section content
    def extract_list_messages(flow_id, section_title, content)
      # Pattern for List Messages in code blocks or structured format
      # Handles both "Title:" and "List Message title:" formats
      list_pattern = /```\s*\n(?:List Message\s+)?[Tt]itle:\s*"([^"]+)"\s*\n((?:Body:[^\n]*\n)?)((?:Button:[^\n]*\n)?)((?:Options:\s*\n)?)(\s*(?:-[^\n]+\n?)+)\s*```/m

      list_counter = 0

      content.scan(list_pattern) do |match|
        list_counter += 1

        title = match[0]&.strip || ""
        body_line = match[1]&.strip || ""
        button_line = match[2]&.strip || ""
        # match[3] is the "Options:" line if present
        options_text = match[4]&.strip || ""

        # Extract body if present
        body = body_line.match(/Body:\s*"?([^"\n]+)"?/)&.captures&.first&.strip

        # Extract button if present
        button = button_line.match(/Button:\s*"?([^"\n]+)"?/)&.captures&.first&.strip

        # Extract options
        options = options_text.scan(/^-\s*(.+)$/).flatten.map(&:strip).reject(&:empty?)

        # Skip if we didn't extract any options
        next if options.empty?

        # Build list message structure
        list_message = {
          title: title,
          body: body,
          button: button,
          options: options
        }.compact

        key = "#{flow_id}_list_#{list_counter}"

        # Require 'json' at the top if not already required
        require 'json' unless defined?(JSON)

        @messages[key] = Models::MessageReference.new(
          flow_id: flow_id,
          text: JSON.generate(list_message), # Store as JSON for structured data
          interpolation_vars: [],
          context: "List Message: #{section_title}"
        )
      end
    end

    # Extract messages from code blocks
    #
    # @param flow_id [String] The flow identifier
    # @param section_title [String] The section title
    # @param content [String] The section content
    def extract_code_block_messages(flow_id, section_title, content)
      # Pattern for messages in code blocks that aren't List Messages
      code_block_pattern = /```(?:ruby|text)?\s*\n([^`]+?)\n```/m

      content.scan(code_block_pattern) do |match|
        block_content = match[0].strip
        next if block_content.empty?

        # Skip if it looks like code (contains Ruby keywords)
        next if block_content.match?(/\b(def|class|module|if|elsif|case|when|return)\b/)

        # Skip if already processed as List Message
        next if block_content.match?(/Title:\s*"/)

        # This might be a flow description or multiline message
        # Only process if it looks like actual message text
        next unless block_content.match?(/[¡!¿?😊👋🔧📱]/)

        vars = extract_interpolation_variables(block_content)
        converted_text = convert_to_rails_syntax(block_content)

        key = "#{flow_id}_code_block"

        @messages[key] = Models::MessageReference.new(
          flow_id: flow_id,
          text: converted_text,
          interpolation_vars: vars,
          context: "Code block message: #{section_title}"
        )
      end
    end



    # Extract interpolation variables from message text
    #
    # Detects placeholders in format: [variable_name]
    # Examples: [client_name], [provider_phone], [keyword detected]
    #
    # @param text [String] Message text with placeholders
    # @return [Array<String>] List of variable names
    def extract_interpolation_variables(text)
      # Find all [variable_name] patterns
      variables = text.scan(/\[([^\]]+)\]/).flatten

      # Filter out patterns that don't look like interpolation variables
      variables = variables.select do |var|
        # Must not start with a quote
        !var.start_with?('"', "'") &&
          # Must not end with a quote
          !var.end_with?('"', "'") &&
          # Must not be all uppercase (likely an ENV var)
          var != var.upcase &&
          # Should look like a variable name (lowercase with underscores or spaces)
          var.match?(/^[a-z][a-z0-9_\s]*$/i)
      end

      # Convert variable names to Rails convention
      variables.map { |var| normalize_variable_name(var) }.uniq
    end

    # Convert message text from v5 placeholder syntax to Rails I18n syntax
    #
    # Converts [variable_name] to %{variable_name}
    #
    # @param text [String] Message text with [variable] placeholders
    # @return [String] Message text with %{variable} placeholders
    def convert_to_rails_syntax(text)
      # Replace [variable_name] with %{variable_name}
      text.gsub(/\[([^\]]+)\]/) do |_match|
        var_name = normalize_variable_name(Regexp.last_match(1))
        "%{#{var_name}}"
      end
    end

    # Normalize variable name to Rails convention
    #
    # Converts descriptive names like "client_name" to "name",
    # "provider_phone" to "phone", etc.
    #
    # @param var_name [String] Variable name from v5 spec
    # @return [String] Normalized variable name for Rails
    def normalize_variable_name(var_name)
      # Mapping of v5 spec variable names to Rails I18n variable names
      mappings = {
        "client_name" => "name",
        "provider_name" => "provider_name",
        "provider_phone" => "phone",
        "client_phone" => "phone",
        "keyword detected" => "keyword",
        "keyword_detected" => "keyword",
        "formatted_date_time" => "date_time",
        "service_description" => "service",
        "duration_minutes" => "duration",
        "address" => "address",
        "phone_prefix" => "prefix",
        "state" => "state",
        "city" => "city",
        "category_needed" => "category",
        "timestamp" => "timestamp",
        "name" => "name",
        "phone" => "phone"
      }

      # Clean and normalize the variable name
      clean_name = var_name.strip.downcase.gsub(/\s+/, "_")

      # Return mapped name or use cleaned name as-is
      mappings[clean_name] || clean_name
    end
  end
end
