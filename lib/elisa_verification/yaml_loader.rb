# frozen_string_literal: true

module ElisaVerification
  # Loader for elisa_es.yml YAML file with message key extraction and flow ID mapping
  #
  # This class loads and parses the elisa_es.yml file, providing access to message keys
  # in dot notation while preserving the original YAML structure. It also extracts flow IDs
  # from YAML comments to enable mapping between YAML keys and v5 specification flows.
  #
  # @example Basic usage
  #   loader = YamlLoader.new('/path/to/elisa_es.yml')
  #   loader.load
  #   keys = loader.all_message_keys
  #   message = loader.get_message('elisa.provider.onboarding.welcome')
  #
  # @example Getting flow IDs from comments
  #   flow_id = loader.flow_id_for('elisa.provider.onboarding.welcome')
  #   # => "P1A"
  class YamlLoader
    # @return [String] Path to the YAML file
    attr_reader :yaml_file_path

    # @return [Hash] Parsed YAML data structure
    attr_reader :data

    # @return [Hash<String, String>] Mapping of YAML key to flow ID extracted from comments
    attr_reader :flow_id_map

    # Initialize the loader with a YAML file path
    #
    # @param yaml_file_path [String] Path to elisa_es.yml
    # @raise [ArgumentError] if yaml_file_path is nil or empty
    # @raise [Errno::ENOENT] if the file does not exist
    def initialize(yaml_file_path)
      raise ArgumentError, "yaml_file_path cannot be nil or empty" if yaml_file_path.nil? || yaml_file_path.empty?
      raise Errno::ENOENT, "File not found: #{yaml_file_path}" unless File.exist?(yaml_file_path)

      @yaml_file_path = yaml_file_path
      @data = nil
      @flow_id_map = {}
      @raw_content = nil
    end

    # Load and parse YAML file
    #
    # This method loads the YAML file using safe mode, parses the structure,
    # and extracts flow ID mappings from comments.
    #
    # @return [Hash] Parsed YAML data structure
    # @raise [YamlParsingError] if YAML syntax is invalid (wraps Psych::SyntaxError with clear message)
    def load
      @raw_content = File.read(@yaml_file_path, encoding: "UTF-8")
      @data = YAML.safe_load(@raw_content, permitted_classes: [], permitted_symbols: [], aliases: true)
      extract_flow_ids_from_comments
      @data
    rescue Psych::SyntaxError => e
      # Requirement 8.1: Handle YAML parsing errors gracefully with clear message and line number
      line_info = e.line ? " at line #{e.line}" : ""
      column_info = e.column ? ", column #{e.column}" : ""
      raise YamlParsingError, "YAML parsing error in #{@yaml_file_path}#{line_info}#{column_info}: #{e.problem}"
    end

    # Get all message keys in dot notation
    #
    # This method recursively traverses the YAML structure and builds a flat list
    # of all message keys using dot notation (e.g., "elisa.provider.onboarding.welcome").
    #
    # @return [Array<String>] All keys in dot notation
    # @raise [RuntimeError] if load has not been called
    def all_message_keys
      raise "YAML file not loaded. Call load() first." if @data.nil?

      keys = []
      flatten_keys(@data, "", keys)
      keys
    end

    # Get message text for a specific key
    #
    # @param key [String] Dot-notation key (e.g., "elisa.provider.onboarding.welcome")
    # @return [String, Hash, Array, nil] Message value (can be string, hash for nested structures, or array for lists)
    # @raise [RuntimeError] if load has not been called
    def get_message(key)
      raise "YAML file not loaded. Call load() first." if @data.nil?

      # Navigate through nested hash using dot notation
      parts = key.split(".")
      current = @data

      parts.each do |part|
        return nil unless current.is_a?(Hash)
        current = current[part]
      end

      current
    end

    # Get flow ID from YAML comments for a key
    #
    # This method looks up the flow ID (e.g., "P1A", "C5A") that was extracted
    # from the comment line above the YAML key.
    #
    # @param key [String] Dot-notation key (e.g., "elisa.provider.onboarding.welcome")
    # @return [String, nil] Flow ID (e.g., "P1A", "C5A") or nil if not found
    def flow_id_for(key)
      @flow_id_map[key]
    end

    private

    # Recursively flatten nested hash structure into dot-notation keys
    #
    # @param hash [Hash] Current level of the nested structure
    # @param prefix [String] Current key prefix (accumulated path)
    # @param result [Array<String>] Accumulator for flattened keys
    def flatten_keys(hash, prefix, result)
      return unless hash.is_a?(Hash)

      hash.each do |key, value|
        full_key = prefix.empty? ? key : "#{prefix}.#{key}"

        if value.is_a?(Hash) && !list_message_structure?(value)
          # Recursively flatten nested hashes (except List Message structures)
          flatten_keys(value, full_key, result)
        else
          # This is a leaf node (string, array, or List Message hash)
          result << full_key
        end
      end
    end

    # Check if a hash represents a List Message structure
    #
    # List Message structures have specific keys: title, body, button, options
    #
    # @param hash [Hash] Hash to check
    # @return [Boolean] true if this is a List Message structure
    def list_message_structure?(hash)
      return false unless hash.is_a?(Hash)

      # List Message structures have these keys
      list_message_keys = %w[title body button options]
      (hash.keys & list_message_keys).any?
    end

    # Extract flow IDs from YAML comments
    #
    # This method parses the raw YAML content line-by-line, looking for comments
    # that contain flow IDs (e.g., "# P1A:", "# C5A:"), and associates them with
    # the next non-comment key found.
    #
    # Comment format examples:
    #   # P1A: Initial welcome message
    #   # C5A: Alert sent to client when emergency detected
    def extract_flow_ids_from_comments
      return if @raw_content.nil?

      current_flow_id = nil
      current_key_path = []
      previous_indent = -1

      @raw_content.each_line do |line|
        # Check for flow ID in comment (format: "# P1A:", "# C5A:", etc.)
        if line =~ /^\s*#\s*([PCpc]\d+[A-Za-z]?):/
          current_flow_id = Regexp.last_match(1).upcase
          next
        end

        # Skip non-key lines (empty lines, values, etc.)
        next unless line =~ /^(\s*)([a-z_]+):\s*(?:"[^"]*"|'[^']*'|[^#\n]*)?(?:#.*)?$/

        indent_level = Regexp.last_match(1).length / 2
        key = Regexp.last_match(2)

        # Adjust key path based on indentation changes
        if indent_level > previous_indent
          # Going deeper - add to path
          current_key_path << key
        elsif indent_level == previous_indent
          # Same level - replace last key
          current_key_path[-1] = key if current_key_path.any?
          current_key_path = [key] if current_key_path.empty?
        else
          # Going up - truncate path and add new key
          current_key_path = current_key_path[0...indent_level]
          current_key_path << key
        end

        previous_indent = indent_level

        # Build full dot-notation key
        full_key = current_key_path.join(".")

        # Associate flow ID with this key if we have one
        if current_flow_id
          @flow_id_map[full_key] = current_flow_id
          current_flow_id = nil # Reset after association
        end
      end
    end
  end

  # Custom error for YAML parsing failures
  # Requirement 8.1: Handle YAML parsing errors gracefully
  class YamlParsingError < StandardError; end
end
