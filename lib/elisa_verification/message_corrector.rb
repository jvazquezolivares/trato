# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module ElisaVerification
  # MessageCorrector applies corrections to YAML messages while preserving
  # file structure, comments, indentation, and formatting.
  #
  # This class uses line-by-line string manipulation (not YAML AST) to ensure
  # that all comments, blank lines, and formatting are preserved exactly.
  #
  # Usage:
  #   corrector = MessageCorrector.new(yaml_file_path, preserve_comments: true)
  #   corrector.apply_correction("elisa.provider.onboarding.welcome", "New message text")
  #   corrector.save(output_path)
  #   corrector.to_yaml_string
  class MessageCorrector
    attr_reader :file_path, :lines, :preserve_comments, :last_backup_path

    # @param file_path [String] Path to the YAML file
    # @param preserve_comments [Boolean] Whether to preserve comments (default: true)
    def initialize(file_path, preserve_comments: true)
      @file_path = file_path
      @preserve_comments = preserve_comments
      @lines = File.readlines(file_path)
      @yaml_data = YAML.load_file(file_path)
      @last_backup_path = nil
    end

    # Apply a correction to a specific message key
    #
    # @param key [String] Dot-notation key (e.g., "elisa.provider.onboarding.welcome")
    # @param new_value [String, Hash, Array] The corrected value
    # @return [Boolean] True if correction was applied, false otherwise
    def apply_correction(key, new_value)
      # Split the key into path parts, skipping the locale prefix if present
      path_parts = key.split('.')
      path_parts.shift if path_parts.first == 'es' # Remove locale prefix if present

      # Find the line number where this key is defined
      line_index = find_key_line(path_parts)

      return false unless line_index

      # Apply the correction based on value type
      case new_value
      when String
        apply_string_correction(line_index, new_value)
      when Hash
        apply_hash_correction(line_index, path_parts, new_value)
      when Array
        apply_array_correction(line_index, new_value)
      else
        false
      end
    end

    # Create a timestamped backup of the original file before making modifications
    #
    # @param source_path [String] Path to the file to backup (defaults to @file_path)
    # @return [String] Path to the created backup file
    # @raise [StandardError] If backup creation fails
    def create_backup(source_path = nil)
      source_path ||= @file_path

      unless File.exist?(source_path)
        raise StandardError, "Cannot create backup: source file does not exist: #{source_path}"
      end

      # Generate timestamped backup filename
      # Format: original_name.backup.YYYYMMDDHHMMSS
      # Example: elisa_es.yml.backup.20250515143000
      timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      backup_path = "#{source_path}.backup.#{timestamp}"

      # Create backup
      FileUtils.cp(source_path, backup_path)

      @last_backup_path = backup_path
      backup_path
    rescue StandardError => e
      raise StandardError, "Failed to create backup: #{e.message}"
    end

    # Save the corrected YAML to a file
    # Automatically creates a timestamped backup before writing if the output path
    # matches the original file path
    #
    # @param output_path [String] Path where to save the corrected YAML
    # @param create_backup_before_save [Boolean] Whether to create backup before saving (default: true)
    # @return [Boolean] True if save was successful
    def save(output_path, create_backup_before_save: true)
      # Validate YAML before writing
      unless validate_yaml_output
        warn "Failed to save YAML: output validation failed"
        return false
      end

      # Create backup if saving to an existing file
      if create_backup_before_save && File.exist?(output_path)
        begin
          create_backup(output_path)
        rescue StandardError => e
          warn "Failed to create backup before save: #{e.message}"
          return false
        end
      end

      # Write the corrected YAML
      File.write(output_path, to_yaml_string)
      true
    rescue StandardError => e
      warn "Failed to save YAML: #{e.message}"
      false
    end

    # Get the current YAML content as a string
    #
    # @return [String] The YAML content with corrections applied
    def to_yaml_string
      @lines.join
    end

    private

    # Validate the corrected YAML output before writing to disk
    #
    # @return [Boolean] True if YAML is valid
    def validate_yaml_output
      yaml_string = to_yaml_string

      # Try to parse the YAML string to ensure it's syntactically valid
      begin
        YAML.safe_load(yaml_string)
        true
      rescue Psych::SyntaxError => e
        warn "YAML validation failed: #{e.message}"
        false
      rescue StandardError => e
        warn "YAML validation error: #{e.message}"
        false
      end
    end

    # Find the line index where a key is defined
    #
    # @param path_parts [Array<String>] Key path parts (e.g., ["elisa", "provider", "onboarding", "welcome"])
    # @return [Integer, nil] Line index or nil if not found
    def find_key_line(path_parts)
      # We track which keys we've found so far and at what indent level
      found_indents = []
      current_path_index = 0

      @lines.each_with_index do |line, index|
        # Skip comments and blank lines
        next if line.strip.start_with?('#') || line.strip.empty?

        # Calculate indentation depth (2 spaces = 1 level)
        indent = line[/^\s*/].length / 2

        # Extract key from line (handle both "key:" and "key: value" formats)
        match = line.match(/^\s*([a-z_]+):/)
        next unless match

        key = match[1]

        # Check if we need to reset our path tracking (we've backed out of a nested structure)
        if found_indents.length > 0 && indent <= found_indents.last
          # Find the appropriate level to reset to
          # We want to keep all found_indents that have indent < current indent
          found_indents = found_indents.take_while { |fi| fi < indent }
          current_path_index = found_indents.length
        end

        # Check if this is the next key we're looking for
        if current_path_index < path_parts.length && key == path_parts[current_path_index]
          # Found the next key in our path!
          found_indents << indent
          current_path_index += 1

          # If we've matched all parts of the path, return this line index
          return index if current_path_index == path_parts.length
        end
      end

      nil
    end

    # Apply correction for a simple string value
    #
    # @param line_index [Integer] Index of the line to modify
    # @param new_value [String] New string value
    # @return [Boolean] True if applied successfully
    def apply_string_correction(line_index, new_value)
      line = @lines[line_index]
      indent = line[/^\s*/]
      key = line.match(/^\s*([a-z_]+):/)[1]

      # Determine if the value should be quoted
      needs_quotes = needs_quoting?(new_value)

      # Check if the current line has the value on the same line or next line
      if line.match(/:\s*["']?(.+)["']?\s*$/)
        # Value is on the same line - replace it
        if needs_quotes
          # Escape quotes in the value
          escaped_value = new_value.gsub('"', '\\"')
          @lines[line_index] = "#{indent}#{key}: \"#{escaped_value}\"\n"
        else
          @lines[line_index] = "#{indent}#{key}: #{new_value}\n"
        end
      else
        # Value might be on next line (multiline string)
        # For now, we'll replace it on the same line
        if needs_quotes
          escaped_value = new_value.gsub('"', '\\"')
          @lines[line_index] = "#{indent}#{key}: \"#{escaped_value}\"\n"
        else
          @lines[line_index] = "#{indent}#{key}: #{new_value}\n"
        end
      end

      true
    end

    # Apply correction for a hash value
    #
    # @param line_index [Integer] Index of the line to modify
    # @param path_parts [Array<String>] Key path parts
    # @param new_value [Hash] New hash value
    # @return [Boolean] True if applied successfully
    def apply_hash_correction(line_index, path_parts, new_value)
      # For hash corrections, we need to recursively apply each key
      # This is complex and should be handled case-by-case
      # For now, we'll just handle simple cases
      warn "Hash corrections not fully implemented yet"
      false
    end

    # Apply correction for an array value
    #
    # @param line_index [Integer] Index of the line to modify
    # @param new_value [Array] New array value
    # @return [Boolean] True if applied successfully
    def apply_array_correction(line_index, new_value)
      line = @lines[line_index]
      indent = line[/^\s*/]
      key = line.match(/^\s*([a-z_]+):/)[1]

      # Find where the current array ends
      array_start = line_index
      array_end = find_array_end(array_start)

      # Build new array lines with proper indentation
      new_lines = ["#{indent}#{key}:\n"]
      item_indent = indent + "  "

      new_value.each do |item|
        if needs_quoting?(item)
          escaped_item = item.gsub('"', '\\"')
          new_lines << "#{item_indent}- \"#{escaped_item}\"\n"
        else
          new_lines << "#{item_indent}- #{item}\n"
        end
      end

      # Replace the old array lines with new ones
      @lines[array_start..array_end] = new_lines

      true
    end

    # Find the end of an array starting at the given line
    #
    # @param start_index [Integer] Starting line index
    # @return [Integer] Ending line index
    def find_array_end(start_index)
      start_line = @lines[start_index]
      start_indent = start_line[/^\s*/].length

      (start_index + 1...@lines.length).each do |i|
        line = @lines[i]
        next if line.strip.empty? || line.strip.start_with?('#')

        indent = line[/^\s*/].length

        # If we find a line with same or less indentation that's not a list item, array has ended
        if indent <= start_indent && !line.strip.start_with?('-')
          return i - 1
        end
      end

      @lines.length - 1
    end

    # Determine if a string value needs to be quoted in YAML
    #
    # @param value [String] The string value to check
    # @return [Boolean] True if the value needs quotes
    def needs_quoting?(value)
      # Strings need quoting if they:
      # - Start or end with whitespace
      # - Contain special YAML characters: : { } [ ] , & * # ? | - < > = ! % @ `
      # - Contain quotes
      # - Start with special indicators like >, |, *, &, !
      # - Contain newlines

      return true if value.strip != value # Leading/trailing whitespace
      return true if value.match?(/[:\{\}\[\],&*#?|\-<>=!%@`'"\\]/) # Special chars
      return true if value.match?(/^[>|*&!]/) # Special indicators at start
      return true if value.include?("\n") # Newlines
      return true if value =~ /^\d/ # Starts with digit (might be interpreted as number)

      false
    end
  end
end
