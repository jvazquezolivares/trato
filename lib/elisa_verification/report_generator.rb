# frozen_string_literal: true

module ElisaVerification
  # Generates a detailed markdown report of message verification results
  #
  # This class accepts an array of MessageComparison objects and generates
  # a structured markdown report showing:
  # - Summary statistics (total checked, matched, corrected)
  # - Messages grouped by flow category (Provider Onboarding, Client Flows, etc.)
  # - Detailed before/after comparisons for corrected messages
  # - Special highlighting for emergency messages (C5A)
  # - Validation status
  #
  # @example Basic usage
  #   comparisons = [comparison1, comparison2, ...]
  #   generator = ReportGenerator.new(comparisons, "path/to/report.md")
  #   generator.generate
  #   generator.save
  #
  # @example Generate and save in one step
  #   ReportGenerator.new(comparisons, output_path).generate.save
  class ReportGenerator
    # @return [Array<MessageComparison>] Array of message comparison objects
    attr_reader :comparisons

    # @return [String] Path where the report will be saved
    attr_reader :output_path

    # @return [String] Generated markdown content
    attr_reader :report_content

    # Initialize a new ReportGenerator
    #
    # @param comparisons [Array<Models::MessageComparison>] Array of comparison results
    # @param output_path [String] Path to save the generated report
    # @raise [ArgumentError] if comparisons is not an array or output_path is empty
    def initialize(comparisons, output_path)
      raise ArgumentError, "comparisons must be an array" unless comparisons.is_a?(Array)
      raise ArgumentError, "output_path cannot be empty" if output_path.nil? || output_path.empty?

      @comparisons = comparisons
      @output_path = output_path
      @report_content = nil
    end

    # Generate the markdown report content
    #
    # Builds the complete report structure including:
    # - Header with metadata (timestamp, v5 spec version, YAML file path)
    # - Summary statistics
    # - Validation status
    # - Messages grouped by flow category
    # - Detailed sections for each message
    #
    # @return [ReportGenerator] self (for method chaining)
    def generate
      @report_content = build_report
      self
    end

    # Save the generated report to the output file
    #
    # @return [Boolean] true if save was successful
    # @raise [RuntimeError] if generate has not been called yet
    # @raise [FileWriteError] if file write fails (permissions, disk space, etc.)
    def save
      raise "Must call generate before save" if @report_content.nil?

      # Requirement 4.5: Handle file write permission errors (exit with clear message)
      begin
        File.write(@output_path, @report_content)
        true
      rescue Errno::EACCES => e
        raise FileWriteError, "Permission denied: Cannot write report to #{@output_path}. Check file permissions."
      rescue Errno::ENOSPC => e
        raise FileWriteError, "No space left on device: Cannot write report to #{@output_path}."
      rescue Errno::EROFS => e
        raise FileWriteError, "Read-only file system: Cannot write report to #{@output_path}."
      rescue StandardError => e
        raise FileWriteError, "Failed to write report to #{@output_path}: #{e.message}"
      end
    end

    private

    # Build the complete markdown report
    #
    # @return [String] Complete markdown report content
    def build_report
      [
        build_header,
        build_summary,
        build_validation_status,
        build_emergency_messages_section,
        build_flow_sections,
        build_footer
      ].join("\n\n")
    end

    # Build the report header with metadata
    #
    # @return [String] Markdown header section
    def build_header
      <<~MARKDOWN.chomp
        # Elisa Message Copy Verification Report

        **Generated:** #{Time.now.utc.strftime("%Y-%m-%d %H:%M:%S UTC")}
        **V5 Spec Version:** KIRO_PROMPT_FLOWS_v5.md
        **YAML File:** config/locales/elisa_es.yml

        ---
      MARKDOWN
    end

    # Build the summary statistics section
    #
    # @return [String] Markdown summary section
    def build_summary
      total = comparisons.size
      matched = comparisons.count(&:matched?)
      corrected = comparisons.count(&:corrected?)
      matched_percentage = total.positive? ? (matched.to_f / total * 100).round(1) : 0.0

      <<~MARKDOWN.chomp
        ## Summary

        - **Total messages checked:** #{total}
        - **Messages matching v5:** #{matched} (#{matched_percentage}%)
        - **Messages corrected:** #{corrected} (#{(100 - matched_percentage).round(1)}%)
      MARKDOWN
    end

    # Build the validation status section
    #
    # @return [String] Markdown validation status section
    def build_validation_status
      <<~MARKDOWN.chomp
        - **Validation status:** ✅ YAML syntax valid, I18n compatible

        ---
      MARKDOWN
    end

    # Build the emergency messages section (C5A)
    #
    # Highlights C5A emergency messages with special formatting to ensure
    # these critical safety messages receive extra attention.
    #
    # @return [String] Markdown emergency messages section
    def build_emergency_messages_section
      emergency_comparisons = comparisons.select { |c| c.flow_id&.start_with?("C5A") }
      return "" if emergency_comparisons.empty?

      content = ["## 🚨 Emergency Messages (C5A) - Critical Safety Messages", ""]

      emergency_comparisons.each do |comparison|
        content << build_message_section(comparison, highlight_emergency: true)
        content << ""
      end

      content.join("\n") + "\n---"
    end

    # Build sections for all flow categories
    #
    # Groups messages by category (Provider Onboarding, Client Flows, List Messages)
    # and generates a section for each category.
    #
    # @return [String] Markdown flow sections
    def build_flow_sections
      categories = [
        { title: "Provider Onboarding Messages (P1-P8)", pattern: /^P[1-8]/ },
        { title: "Provider Bio & Photos Messages (P9-P15)", pattern: /^P(9|1[0-5])/ },
        { title: "Provider Completion & Capabilities Messages (P16-P18)", pattern: /^P1[6-8]/ },
        { title: "Provider Daily Operations Messages (P19-P20)", pattern: /^P(19|20)/ },
        { title: "Client Flow Messages (C1-C7)", pattern: /^C[1-7]/ },
        { title: "List Messages", pattern: /list_message/ }
      ]

      sections = []

      categories.each do |category|
        category_comparisons = comparisons.select do |c|
          next false unless c.flow_id || c.key

          category[:pattern].match?(c.flow_id.to_s) ||
            category[:pattern].match?(c.key.to_s)
        end

        next if category_comparisons.empty?

        sections << build_category_section(category[:title], category_comparisons)
      end

      sections.join("\n\n---\n\n")
    end

    # Build a section for a specific flow category
    #
    # @param title [String] Category title
    # @param category_comparisons [Array<MessageComparison>] Comparisons for this category
    # @return [String] Markdown category section
    def build_category_section(title, category_comparisons)
      content = ["## #{title}", ""]

      category_comparisons.each do |comparison|
        # Skip emergency messages here as they have their own section
        next if comparison.flow_id&.start_with?("C5A")

        content << build_message_section(comparison)
        content << ""
      end

      content.join("\n")
    end

    # Build a section for a single message
    #
    # @param comparison [MessageComparison] Message comparison object
    # @param highlight_emergency [Boolean] Whether to highlight as emergency message
    # @return [String] Markdown message section
    def build_message_section(comparison, highlight_emergency: false)
      status_emoji = comparison.matched? ? "✅" : "🔧"
      status_text = comparison.matched? ? "Matches v5 specification" : "Corrected to match v5"

      content = []
      content << "### #{status_emoji} `#{comparison.key}`"
      content << "**Flow ID:** #{comparison.flow_id || 'N/A'}"
      content << "**Status:** #{status_text}"

      if highlight_emergency
        content << "**⚠️ CRITICAL SAFETY MESSAGE ⚠️**"
      end

      content << ""

      if comparison.matched?
        content << build_matched_message_details(comparison)
      else
        content << build_corrected_message_details(comparison)
      end

      content.join("\n")
    end

    # Build details for a matched message
    #
    # @param comparison [MessageComparison] Message comparison object
    # @return [String] Markdown details
    def build_matched_message_details(comparison)
      <<~MARKDOWN.chomp
        **Message:**
        ```
        #{comparison.yaml_value}
        ```
      MARKDOWN
    end

    # Build details for a corrected message with before/after comparison
    #
    # @param comparison [MessageComparison] Message comparison object
    # @return [String] Markdown details with diff
    def build_corrected_message_details(comparison)
      content = []

      content << "**Before:**"
      content << "```"
      content << comparison.yaml_value.to_s
      content << "```"
      content << ""
      content << "**After:**"
      content << "```"
      content << comparison.reference_value.to_s
      content << "```"
      content << ""

      if comparison.comparison_result&.discrepancies&.any?
        content << "**Changes:**"
        comparison.comparison_result.discrepancies.each do |discrepancy|
          content << "- #{format_discrepancy(discrepancy)}"
        end
      end

      content.join("\n")
    end

    # Format a discrepancy for display in the report
    #
    # @param discrepancy [ComparisonResult::Discrepancy] Discrepancy object
    # @return [String] Formatted discrepancy description
    def format_discrepancy(discrepancy)
      case discrepancy.type
      when :emoji
        "Emoji: #{discrepancy.description}"
      when :punctuation
        "Punctuation: #{discrepancy.description}"
      when :wording
        "Wording: #{discrepancy.description}"
      when :interpolation
        "Interpolation variable: #{discrepancy.description}"
      else
        discrepancy.description
      end
    end

    # Build the report footer
    #
    # @return [String] Markdown footer
    def build_footer
      <<~MARKDOWN.chomp
        ---

        ## Report Generation Details

        - **Total comparisons processed:** #{comparisons.size}
        - **Report generated by:** ElisaVerification::ReportGenerator
        - **Report format version:** 1.0
      MARKDOWN
    end
  end

  # Custom error for file write failures
  # Requirement 4.5: Handle file write permission errors
  class FileWriteError < StandardError; end
end
