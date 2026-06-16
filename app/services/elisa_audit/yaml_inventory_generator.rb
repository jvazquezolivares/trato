# frozen_string_literal: true

require_relative 'data_models'
require_relative 'errors'
require_relative 'yaml_syntax_validator'

module ElisaAudit
  # Service to generate structured markdown inventory of all messages in elisa_es.yml
  #
  # This service parses the YAML file, extracts all message keys under elisa.provider.* and
  # elisa.client.*, infers flow IDs from key structure, detects interpolation variables,
  # and tracks line numbers for each message.
  #
  # Purpose:
  #   Generate a complete inventory of current messages for manual PDF comparison during Phase 1 audit.
  #
  # Usage:
  #   generator = ElisaAudit::YamlInventoryGenerator.new
  #   result = generator.call
  #
  #   # Result is a hash with:
  #   # {
  #   #   markdown: "Markdown table content...",
  #   #   entries: [MessageEntry, MessageEntry, ...],
  #   #   stats: { total: 50, provider: 30, client: 20 }
  #   # }
  #
  # Requirements:
  #   - Req 1.1: Generate Phase 1 Audit Report
  #   - Req 21.1: Verify all provider flow messages match PDF
  #   - Req 22.1: Verify all client flow messages match PDF
  #   - Req 25.1: Preserve all existing interpolation variables
  class YamlInventoryGenerator
    # Path to the elisa_es.yml file
    YAML_PATH = Rails.root.join('config', 'locales', 'elisa_es.yml')

    # Output path for the generated inventory
    OUTPUT_PATH = Rails.root.join('.kiro', 'specs', 'elisa-message-copy-verification', 'yaml-inventory.md')

    # Initialize the generator
    def initialize
      @entries = []
      @yaml_content = nil
      @line_map = {}
      @syntax_errors = []
    end

    # Main entry point - generates the complete inventory
    # @return [Hash] Result with markdown, entries, stats, and syntax errors
    # @raise [YamlParseError] if YAML file cannot be parsed
    def call
      load_yaml_with_line_numbers
      validate_yaml_syntax
      extract_messages
      stats = calculate_stats

      markdown = generate_markdown

      {
        markdown: markdown,
        entries: @entries,
        stats: stats,
        syntax_errors: @syntax_errors
      }
    end

    # Saves the generated markdown to the output file
    # @param markdown [String] The markdown content to save
    # @return [String] Path to the saved file
    def save_to_file(markdown)
      FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
      File.write(OUTPUT_PATH, markdown)
      OUTPUT_PATH.to_s
    end

    private

    # Load YAML file and build line number map
    # @raise [YamlParseError] if file cannot be parsed
    def load_yaml_with_line_numbers
      unless File.exist?(YAML_PATH)
        raise YamlParseError, "File not found: #{YAML_PATH}"
      end

      # Read raw content for line number tracking
      raw_content = File.read(YAML_PATH)
      @line_map = build_line_map(raw_content)

      # Parse YAML structure
      @yaml_content = YAML.load_file(YAML_PATH)
    rescue Psych::SyntaxError => e
      raise YamlParseError, "Invalid YAML syntax at line #{e.line}: #{e.message}"
    rescue StandardError => e
      raise YamlParseError, "Error reading YAML file: #{e.message}"
    end

    # Validate YAML syntax for common issues
    # Stores validation errors in @syntax_errors for inclusion in report
    def validate_yaml_syntax
      validator = YamlSyntaxValidator.new(YAML_PATH)
      @syntax_errors = validator.validate
    end

    # Build a map of YAML keys to line numbers
    # @param raw_content [String] Raw YAML file content
    # @return [Hash] Map of key paths to line numbers
    def build_line_map(raw_content)
      line_map = {}
      current_path = []
      indent_stack = [-1]

      raw_content.each_line.with_index(1) do |line, line_number|
        # Skip comments and empty lines
        next if line.strip.empty? || line.strip.start_with?('#')

        # Calculate indentation level
        indent = line[/^ */].length

        # Skip if this is not a key-value line
        next unless line.include?(':')

        # Extract key name (before the colon)
        key = line.split(':', 2).first.strip

        # Adjust path based on indentation
        while indent <= indent_stack.last && current_path.any?
          current_path.pop
          indent_stack.pop
        end

        # Add key to current path
        current_path << key
        indent_stack << indent

        # Store line number for this key path
        key_path = current_path.join('.')
        line_map[key_path] = line_number
      end

      line_map
    end

    # Extract all messages from the YAML structure
    # Processes both provider and client message hierarchies
    def extract_messages
      return unless @yaml_content && @yaml_content['es'] && @yaml_content['es']['elisa']

      elisa_content = @yaml_content['es']['elisa']

      # Extract provider messages
      extract_messages_recursive(elisa_content['provider'], 'es.elisa.provider', 'provider') if elisa_content['provider']

      # Extract client messages
      extract_messages_recursive(elisa_content['client'], 'es.elisa.client', 'client') if elisa_content['client']
    end

    # Recursively traverse YAML structure to find message strings
    # @param node [Hash, String] Current YAML node being processed
    # @param key_path [String] Current dot-notation key path
    # @param scope [String] Either 'provider' or 'client'
    def extract_messages_recursive(node, key_path, scope)
      case node
      when Hash
        node.each do |key, value|
          new_path = "#{key_path}.#{key}"
          extract_messages_recursive(value, new_path, scope)
        end
      when String
        # Found a message string - create entry
        create_message_entry(key_path, node, scope)
      when Array
        # Handle arrays (e.g., list message options)
        node.each_with_index do |item, index|
          if item.is_a?(String)
            create_message_entry("#{key_path}[#{index}]", item, scope)
          end
        end
      end
    end

    # Create a MessageEntry for a found message string
    # @param key_path [String] Full YAML key path
    # @param content [String] Message text content
    # @param scope [String] Either 'provider' or 'client'
    def create_message_entry(key_path, content, scope)
      # Infer flow ID from key structure
      flow_id = infer_flow_id(key_path, scope)

      # Extract interpolation variables
      variables = extract_variables(content)

      # Find line number
      line_number = find_line_number(key_path)

      # Create and store entry
      entry = MessageEntry.new(
        flow_id: flow_id,
        yaml_key: key_path,
        content: content,
        line_number: line_number,
        variables: variables
      )

      @entries << entry
    end

    # Infer flow ID from YAML key structure
    # @param key_path [String] Full YAML key path
    # @param scope [String] Either 'provider' or 'client'
    # @return [String] Inferred flow ID (e.g., 'P1A', 'C7A', or 'Unknown')
    def infer_flow_id(key_path, scope)
      # Provider flow mappings
      if scope == 'provider'
        return 'P1A' if key_path.include?('onboarding.welcome')
        return 'P1B' if key_path.include?('onboarding.decline') || key_path.include?('decline_reasons')
        return 'P2A' if key_path.include?('onboarding.name')
        return 'P2B' if key_path.include?('onboarding.greeting')
        return 'P3A' if key_path.include?('onboarding.categories') || key_path.include?('primary_trade')
        return 'P3E' if key_path.include?('onboarding.city') || key_path.include?('onboarding.area')
        return 'P4' if key_path.include?('onboarding.price') || key_path.include?('price_range')
        return 'P5' if key_path.include?('onboarding.experience') || key_path.include?('list_messages.experience')
        return 'P6A' if key_path.include?('onboarding.specialties')
        return 'P7A' if key_path.include?('onboarding.specialized_work')
        return 'P9A' if key_path.include?('bio.question')
        return 'P10A' if key_path.include?('bio.approval') || key_path.include?('bio.resend') || key_path.include?('bio.regenerat')
        return 'P11A' if key_path.include?('photos.profile')
        return 'P12A' if key_path.include?('photos.work')
        return 'P13A' if key_path.include?('facebook')
        return 'P14A' if key_path.include?('email')
        return 'P16A' if key_path.include?('completion')
        return 'P18' if key_path.include?('capabilities') || key_path.include?('auto_reply')
        return 'P19' if key_path.include?('morning_summary')
        return 'P17' if key_path.include?('financial_summary')
      end

      # Client flow mappings
      if scope == 'client'
        return 'C2A' if key_path.include?('region_detection')
        return 'C4A' if key_path.include?('appointment')
        return 'C5A' if key_path.include?('emergency')
        return 'C7A' if key_path.include?('review')
        return 'C7A' if key_path.include?('ratings')
      end

      # Default if cannot infer
      "Unknown (#{scope})"
    end

    # Extract interpolation variables from message text
    # @param content [String] Message text
    # @return [Array<String>] List of variable names (without %{} syntax)
    def extract_variables(content)
      # Match Rails i18n interpolation syntax: %{variable_name}
      variables = content.scan(/%\{([^}]+)\}/).flatten
      variables.uniq
    end

    # Find line number for a key path in the YAML file
    # @param key_path [String] Full YAML key path
    # @return [Integer, nil] Line number or nil if not found
    def find_line_number(key_path)
      # Try exact match first
      return @line_map[key_path] if @line_map[key_path]

      # For array entries like "key[0]", try without the index
      base_key = key_path.gsub(/\[\d+\]$/, '')
      return @line_map[base_key] if @line_map[base_key]

      # Try progressively shorter paths
      parts = key_path.split('.')
      while parts.any?
        path = parts.join('.')
        return @line_map[path] if @line_map[path]
        parts.pop
      end

      nil
    end

    # Calculate statistics about the extracted messages
    # @return [Hash] Statistics with total, provider, and client counts
    def calculate_stats
      provider_count = @entries.count { |e| e.flow_id.to_s.start_with?('P') }
      client_count = @entries.count { |e| e.flow_id.to_s.start_with?('C') }
      unknown_count = @entries.count { |e| e.flow_id.to_s.start_with?('Unknown') }

      {
        total: @entries.count,
        provider: provider_count,
        client: client_count,
        unknown: unknown_count
      }
    end

    # Generate markdown table from extracted entries
    # @return [String] Formatted markdown content
    def generate_markdown
      output = []

      # Header
      output << "# Elisa Message Inventory"
      output << ""
      output << "Generated: #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}"
      output << "Source: `#{YAML_PATH}`"
      output << ""

      # Statistics
      stats = calculate_stats
      output << "## Statistics"
      output << ""
      output << "- **Total messages:** #{stats[:total]}"
      output << "- **Provider messages:** #{stats[:provider]}"
      output << "- **Client messages:** #{stats[:client]}"
      output << "- **Unknown/unmapped:** #{stats[:unknown]}"
      output << ""

      # Syntax validation results
      if @syntax_errors.any?
        output << "## ⚠️ YAML Syntax Validation Errors"
        output << ""
        output << "The following syntax issues were found in the YAML file:"
        output << ""
        output << generate_syntax_errors_table
        output << ""
      else
        output << "## ✅ YAML Syntax Validation"
        output << ""
        output << "No syntax errors detected. The YAML file is valid."
        output << ""
      end

      # Provider messages table
      provider_entries = @entries.select { |e| e.flow_id.to_s.start_with?('P') }
      if provider_entries.any?
        output << "## Provider Messages (P1-P20)"
        output << ""
        output << generate_table(provider_entries)
        output << ""
      end

      # Client messages table
      client_entries = @entries.select { |e| e.flow_id.to_s.start_with?('C') }
      if client_entries.any?
        output << "## Client Messages (C1-C7)"
        output << ""
        output << generate_table(client_entries)
        output << ""
      end

      # Unknown messages table
      unknown_entries = @entries.select { |e| e.flow_id.to_s.start_with?('Unknown') }
      if unknown_entries.any?
        output << "## Unknown/Unmapped Messages"
        output << ""
        output << generate_table(unknown_entries)
        output << ""
      end

      output.join("\n")
    end

    # Generate markdown table for a set of entries
    # @param entries [Array<MessageEntry>] Entries to include in table
    # @return [String] Markdown table
    def generate_table(entries)
      table = []

      # Table header
      table << "| Flow ID | YAML Key | Current Message | Variables | Line |"
      table << "|---------|----------|-----------------|-----------|------|"

      # Sort entries by flow ID and line number
      sorted_entries = entries.sort_by { |e| [e.flow_id.to_s, e.line_number || 0] }

      # Table rows
      sorted_entries.each do |entry|
        # Truncate long messages for readability
        message = truncate_message(entry.content)

        # Format variables
        variables = entry.has_variables? ? entry.formatted_variables : '-'

        # Format line number
        line = entry.line_number || '?'

        table << "| #{entry.flow_id} | `#{entry.yaml_key}` | #{message} | #{variables} | #{line} |"
      end

      table.join("\n")
    end

    # Generate markdown table for syntax errors
    # @return [String] Markdown table of syntax errors
    def generate_syntax_errors_table
      table = []

      # Table header
      table << "| Severidad | Tipo | Línea | Clave YAML | Mensaje |"
      table << "|-----------|------|-------|------------|---------|"

      # Sort errors by severity (critical first) and then by line number
      severity_order = { critical: 0, warning: 1, info: 2 }
      sorted_errors = @syntax_errors.sort_by do |error|
        [severity_order[error.severity] || 3, error.line_number || 0]
      end

      # Table rows
      sorted_errors.each do |error|
        severity = error.severity_badge
        type = error.error_type.to_s.capitalize
        line = error.line_number || 'N/A'
        key = error.key_path || '-'
        message = error.message.gsub('|', '\\|') # Escape pipes for markdown

        table << "| #{severity} | #{type} | #{line} | `#{key}` | #{message} |"
      end

      table.join("\n")
    end

    # Truncate message text for display in table
    # @param text [String] Message text
    # @param max_length [Integer] Maximum length before truncation
    # @return [String] Truncated text
    def truncate_message(text, max_length = 60)
      # First, escape special markdown characters and normalize whitespace
      # Replace newlines with spaces for single-line display
      normalized = text.gsub("\n", ' ').gsub(/\s+/, ' ').strip

      # Escape pipe characters that would break markdown table
      escaped = normalized.gsub('|', '\\|')

      # Truncate if needed
      return escaped if escaped.length <= max_length

      "#{escaped[0...max_length]}..."
    end
  end
end
