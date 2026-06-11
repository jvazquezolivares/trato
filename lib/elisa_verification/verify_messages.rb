#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'yaml'
require 'json'

# Require all component files
require_relative 'models/message_reference'
require_relative 'models/comparison_result'
require_relative 'models/message_comparison'
require_relative 'models/validation_result'
require_relative 'v5_spec_parser'
require_relative 'yaml_loader'
require_relative 'message_comparator'
require_relative 'message_corrector'
require_relative 'yaml_validator'
require_relative 'report_generator'

# Main entry point for Elisa message copy verification
# This script compares message copies in elisa_es.yml against KIRO_PROMPT_FLOWS_v5.md
# and optionally applies corrections.
#
# Requirements: 1.1, 6.1
module ElisaVerification
  class CLI
    DEFAULT_YAML_PATH = 'config/locales/elisa_es.yml'
    DEFAULT_SPEC_PATH = '../KIRO_PROMPT_FLOWS_v5.md'
    DEFAULT_REPORT_PATH = '../.kiro/specs/elisa-message-copy-verification/verification-report.md'

    attr_reader :options

    def initialize(args)
      @options = {
        apply: false,
        yaml_path: DEFAULT_YAML_PATH,
        spec_path: DEFAULT_SPEC_PATH,
        report_path: DEFAULT_REPORT_PATH,
        verbose: false,
        skip_i18n: false
      }
      parse_arguments(args)
    end

    def run
      if @options[:help]
        puts @option_parser
        return 0
      end

      display_configuration if @options[:verbose]

      # Validation will be implemented in subsequent tasks
      validate_paths

      puts "=== Elisa Message Copy Verification ==="
      puts
      puts "Configuration:"
      puts "  YAML file: #{@options[:yaml_path]}"
      puts "  Spec file: #{@options[:spec_path]}"
      puts "  Report: #{@options[:report_path]}"
      puts "  Apply corrections: #{@options[:apply] ? 'YES' : 'NO (dry-run)'}"
      puts "  Skip I18n validation: #{@options[:skip_i18n] ? 'YES' : 'NO'}"
      puts

      # Task 11.2: Wire all components together
      run_verification

      0
    rescue ElisaVerification::YamlParsingError => e
      # Requirement 8.1: Handle YAML parsing errors gracefully - exit with clear message and line number
      warn "\n❌ YAML Parsing Error:"
      warn e.message
      warn "\nPlease fix the YAML syntax error before running verification."
      1
    rescue ElisaVerification::FileWriteError => e
      # Requirement 4.5: Handle file write permission errors - exit with clear message
      warn "\n❌ File Write Error:"
      warn e.message
      warn "\nPlease check file permissions and disk space."
      1
    rescue Errno::ENOENT => e
      warn "\n❌ File Not Found:"
      warn e.message
      1
    rescue StandardError => e
      warn "\n❌ Unexpected Error: #{e.message}"
      warn e.backtrace.join("\n") if @options[:verbose]
      1
    end

    # Task 11.2: Wire all components together
    # Instantiate components and run verification workflow
    def run_verification
      # Step 1: Instantiate V5SpecParser and parse specification
      puts "📖 Loading V5 specification..."
      v5_parser = V5SpecParser.new(@options[:spec_path])
      v5_messages = v5_parser.parse
      puts "✓ Parsed #{v5_messages.size} reference messages from #{@options[:spec_path]}"
      puts

      # Step 2: Instantiate YamlLoader and load YAML file
      puts "📝 Loading YAML file..."
      yaml_loader = YamlLoader.new(@options[:yaml_path])
      yaml_loader.load
      yaml_keys = yaml_loader.all_message_keys
      puts "✓ Loaded #{yaml_keys.size} message keys from #{@options[:yaml_path]}"
      puts

      # Step 3: Iterate through YAML keys and compare against v5 references
      puts "🔍 Comparing messages..."
      comparisons = []
      comparator = MessageComparator.new
      skipped_no_flow_id = []
      skipped_no_reference = []

      yaml_keys.each do |key|
        # Get YAML message value
        yaml_value = yaml_loader.get_message(key)

        # Skip non-string values for now (nested structures)
        next unless yaml_value.is_a?(String)

        # Get flow ID from YAML comments
        flow_id = yaml_loader.flow_id_for(key)

        # Requirement 8.1: Handle missing flow ID comments (log warning, skip that comparison)
        if flow_id.nil?
          skipped_no_flow_id << key
          verbose_log("Skipping #{key} - no flow ID found in comments")
          next
        end

        # Get reference message from v5 spec
        # Try exact match first, then try with suffixes (_msg_1, _code_block, etc.)
        reference = v5_parser.message_for(flow_id)

        if reference.nil?
          # Try with common suffixes that the parser adds
          possible_keys = [
            "#{flow_id}_msg_1",
            "#{flow_id}_msg_2",
            "#{flow_id}_code_block",
            "#{flow_id}_list_1"
          ]

          reference = possible_keys.map { |k| v5_parser.message_for(k) }.compact.first
        end

        # Skip if no reference found
        if reference.nil?
          skipped_no_reference << { key: key, flow_id: flow_id }
          verbose_log("Skipping #{key} (#{flow_id}) - no v5 reference found")
          next
        end

        # Compare YAML message against v5 reference
        comparison_result = comparator.compare(yaml_value, reference)

        # Create MessageComparison object
        comparison = Models::MessageComparison.new(
          key: key,
          flow_id: flow_id,
          yaml_value: yaml_value,
          reference_value: reference.text,
          comparison_result: comparison_result,
          corrected: false # Corrections will be applied in task 11.4
        )

        comparisons << comparison
      end

      puts "✓ Analyzed #{comparisons.size} messages"
      matched_count = comparisons.count(&:matched?)
      corrected_count = comparisons.size - matched_count
      matched_percentage = comparisons.size.positive? ? (matched_count.to_f / comparisons.size * 100).round(1) : 0.0

      puts "  - #{matched_count} match v5 specification (#{matched_percentage}%)"
      puts "  - #{corrected_count} require corrections (#{(100 - matched_percentage).round(1)}%)"

      # Requirement 8.1: Log warnings for skipped messages
      if skipped_no_flow_id.any?
        puts
        warn "⚠️  Warning: #{skipped_no_flow_id.size} message(s) skipped - no flow ID comment found:"
        skipped_no_flow_id.first(5).each { |key| warn "   - #{key}" }
        warn "   ... and #{skipped_no_flow_id.size - 5} more" if skipped_no_flow_id.size > 5
      end

      if skipped_no_reference.any?
        puts
        warn "⚠️  Warning: #{skipped_no_reference.size} message(s) skipped - no v5 reference found:"
        skipped_no_reference.first(5).each { |item| warn "   - #{item[:key]} (#{item[:flow_id]})" }
        warn "   ... and #{skipped_no_reference.size - 5} more" if skipped_no_reference.size > 5
      end

      puts

      # Step 4: Generate report using ReportGenerator
      puts "📊 Generating report..."
      generator = ReportGenerator.new(comparisons, @options[:report_path])
      generator.generate
      generator.save
      puts "✓ Report saved to #{@options[:report_path]}"
      puts

      # Task 11.3: Dry-run mode (default behavior)
      # Display summary and prompt user
      display_verification_summary(comparisons, corrected_count)

      # Task 11.4: Apply corrections if --apply flag is set
      if @options[:apply]
        apply_corrections(comparisons, yaml_loader)
      end
    rescue StandardError => e
      warn "Verification failed: #{e.message}"
      warn e.backtrace.join("\n") if @options[:verbose]
      raise
    end

    # Task 11.3: Display verification summary for dry-run mode
    # Shows findings and prompts user to run with --apply if corrections needed
    def display_verification_summary(comparisons, corrections_needed)
      puts "=" * 60
      puts "VERIFICATION SUMMARY"
      puts "=" * 60
      puts

      if corrections_needed.zero?
        puts "✅ All messages match v5 specification!"
        puts "   No corrections needed."
      else
        puts "📋 Findings:"
        puts "   - Total messages checked: #{comparisons.size}"
        puts "   - Messages matching v5: #{comparisons.count(&:matched?)}"
        puts "   - Messages needing correction: #{corrections_needed}"
        puts

        puts "📄 Detailed report available at:"
        puts "   #{@options[:report_path]}"
        puts

        unless @options[:apply]
          puts "⚠️  DRY-RUN MODE"
          puts "   No files have been modified."
          puts "   Review the report above, then run with --apply to make changes:"
          puts
          puts "   bundle exec ruby #{$PROGRAM_NAME} --apply"
        end
      end
      puts
    end

    # Task 11.4: Add correction application logic (--apply flag)
    # This method:
    # 1. Creates a timestamped backup of the original YAML file
    # 2. Applies all corrections using MessageCorrector
    # 3. Validates corrected YAML using YamlValidator
    # 4. Saves corrected file only if validation passes
    # 5. Displays confirmation message with file paths
    # 6. If validation fails, warns user
    #
    # Requirements: 1.4, 6.1, 8.3, 16.1, 16.6
    def apply_corrections(comparisons, yaml_loader)
      puts "=" * 60
      puts "APPLYING CORRECTIONS"
      puts "=" * 60
      puts

      # Filter out comparisons that need corrections
      corrections_needed = comparisons.reject(&:matched?)

      if corrections_needed.empty?
        puts "✅ No corrections needed - all messages match v5 specification!"
        return
      end

      puts "📝 Preparing to apply #{corrections_needed.size} corrections..."
      puts

      # Step 1: Create timestamped backup of original YAML file
      puts "💾 Creating backup..."
      corrector = MessageCorrector.new(@options[:yaml_path])

      begin
        backup_path = corrector.create_backup
        puts "✓ Backup created: #{backup_path}"
      rescue StandardError => e
        warn "❌ Failed to create backup: #{e.message}"
        warn "   Aborting correction process for safety."
        return
      end

      puts

      # Step 2: Apply all corrections using MessageCorrector
      puts "🔧 Applying corrections..."
      applied_count = 0
      failed_corrections = []

      corrections_needed.each do |comparison|
        verbose_log("Applying correction to #{comparison.key}")

        success = corrector.apply_correction(comparison.key, comparison.reference_value)

        if success
          applied_count += 1
          # Mark comparison as corrected
          comparison.instance_variable_set(:@corrected, true)
        else
          failed_corrections << comparison.key
          verbose_log("Failed to apply correction to #{comparison.key}")
        end
      end

      puts "✓ Applied #{applied_count} corrections"

      if failed_corrections.any?
        puts "⚠️  Failed to apply #{failed_corrections.size} corrections:"
        failed_corrections.each { |key| puts "     - #{key}" }
        puts
      end

      puts

      # Step 3: Validate corrected YAML using YamlValidator
      puts "✅ Validating corrected YAML..."

      # Save to temporary file for validation
      temp_yaml = "#{@options[:yaml_path]}.tmp"

      begin
        File.write(temp_yaml, corrector.to_yaml_string)

        validator = YamlValidator.new(temp_yaml)

        # Validate syntax
        syntax_result = validator.validate_syntax
        if syntax_result.valid?
          puts "✓ YAML syntax valid"
        else
          puts "❌ YAML syntax validation failed:"
          syntax_result.errors.each { |error| puts "     - #{error}" }
          File.delete(temp_yaml)
          puts
          puts "⚠️  Validation failed. Backup preserved at: #{backup_path}"
          puts "   Original file unchanged."
          return
        end

        # Validate I18n (unless skipped)
        unless @options[:skip_i18n]
          i18n_result = validator.validate_i18n
          if i18n_result.valid?
            puts "✓ I18n validation passed"
          else
            puts "⚠️  I18n validation warnings:"
            i18n_result.errors.each { |error| puts "     - #{error}" }
            # Don't abort on I18n warnings, just show them
          end
        end

        puts

        # Step 4: Save corrected file only if validation passes
        puts "💾 Saving corrected YAML file..."

        success = corrector.save(@options[:yaml_path], create_backup_before_save: false)

        if success
          # Clean up temporary file
          File.delete(temp_yaml) if File.exist?(temp_yaml)

          # Step 5: Display confirmation message with file paths
          puts "✅ SUCCESS!"
          puts
          puts "📄 Files:"
          puts "   Original backup: #{backup_path}"
          puts "   Corrected file:  #{@options[:yaml_path]}"
          puts
          puts "📊 Summary:"
          puts "   - Corrections applied: #{applied_count}/#{corrections_needed.size}"
          puts "   - YAML validation: ✅ Passed"
          puts "   - I18n validation: #{@options[:skip_i18n] ? '⊘ Skipped' : '✅ Passed'}"
          puts
          puts "✨ Message copies now match v5 specification!"
          puts
        else
          # Clean up temporary file
          File.delete(temp_yaml) if File.exist?(temp_yaml)

          puts "❌ Failed to save corrected YAML file"
          puts
          puts "⚠️  Backup preserved at: #{backup_path}"
          puts "   Original file unchanged."
        end

      rescue StandardError => e
        # Clean up temporary file
        File.delete(temp_yaml) if File.exist?(temp_yaml)

        warn "❌ Error during validation: #{e.message}"
        warn e.backtrace.join("\n") if @options[:verbose]
        puts
        puts "⚠️  Backup preserved at: #{backup_path}"
        puts "   Original file unchanged."
      end
    end

    # Log verbose output if verbose mode is enabled
    def verbose_log(message)
      puts "  [DEBUG] #{message}" if @options[:verbose]
    end

    private

    def parse_arguments(args)
      @option_parser = OptionParser.new do |opts|
        opts.banner = "Usage: verify_messages.rb [options]"
        opts.separator ""
        opts.separator "Verify Elisa message copies against v5 specification"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-h", "--help", "Show this help message") do
          @options[:help] = true
        end

        opts.on("-a", "--apply", "Apply corrections to YAML file (default: dry-run)") do
          @options[:apply] = true
        end

        opts.on("-y", "--yaml PATH", "Path to elisa_es.yml (default: #{DEFAULT_YAML_PATH})") do |path|
          @options[:yaml_path] = path
        end

        opts.on("-s", "--spec PATH", "Path to v5 spec (default: #{DEFAULT_SPEC_PATH})") do |path|
          @options[:spec_path] = path
        end

        opts.on("-r", "--report PATH", "Path for report output (default: #{DEFAULT_REPORT_PATH})") do |path|
          @options[:report_path] = path
        end

        opts.on("-v", "--verbose", "Enable verbose output") do
          @options[:verbose] = true
        end

        opts.on("--skip-i18n", "Skip I18n validation (faster but less safe)") do
          @options[:skip_i18n] = true
        end

        opts.separator ""
        opts.separator "Examples:"
        opts.separator "  # Dry-run mode (analyze only, no changes)"
        opts.separator "  ruby verify_messages.rb"
        opts.separator ""
        opts.separator "  # Apply corrections"
        opts.separator "  ruby verify_messages.rb --apply"
        opts.separator ""
        opts.separator "  # Custom paths with verbose output"
        opts.separator "  ruby verify_messages.rb --yaml custom.yml --spec custom_spec.md --verbose"
      end

      @option_parser.parse!(args)
    rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
      warn "Error parsing arguments: #{e.message}"
      warn @option_parser
      exit 1
    end

    def display_configuration
      puts "Debug: Configuration loaded"
      puts "  apply: #{@options[:apply]}"
      puts "  yaml_path: #{@options[:yaml_path]}"
      puts "  spec_path: #{@options[:spec_path]}"
      puts "  report_path: #{@options[:report_path]}"
      puts "  verbose: #{@options[:verbose]}"
      puts "  skip_i18n: #{@options[:skip_i18n]}"
      puts
    end

    def validate_paths
      unless File.exist?(@options[:yaml_path])
        raise "YAML file not found: #{@options[:yaml_path]}"
      end

      unless File.exist?(@options[:spec_path])
        raise "Spec file not found: #{@options[:spec_path]}"
      end

      # Ensure report directory exists
      report_dir = File.dirname(@options[:report_path])
      unless Dir.exist?(report_dir)
        raise "Report directory not found: #{report_dir}"
      end
    end
  end
end

# Script entry point
if __FILE__ == $PROGRAM_NAME
  cli = ElisaVerification::CLI.new(ARGV)
  exit cli.run
end
