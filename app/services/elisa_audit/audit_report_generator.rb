# frozen_string_literal: true

require_relative 'data_models'
require_relative 'ai_usage_rules'
require_relative 'errors'
require_relative 'placeholder_consistency_analyzer'

module ElisaAudit
  # Service to aggregate all audit findings and generate comprehensive markdown report
  #
  # This service acts as the main orchestrator for Phase 1 audit report generation.
  # It accepts outputs from YamlInventoryGenerator, AiUsageAnalyzer, and WhatsAppTemplateDetector,
  # then aggregates and formats everything into a comprehensive markdown report.
  #
  # Purpose:
  #   Generate the Phase 1 audit report with nine main sections:
  #   1. Executive Summary - High-level statistics and findings
  #   2. YAML Syntax Validation - Pre-existing syntax errors in elisa_es.yml
  #   3. Manual Comparison Template - Template for developer to fill during PDF comparison
  #   4. AI Usage Violations - All detected AI usage issues
  #   5. WhatsApp Message Templates - Required templates for Meta approval
  #   6. Placeholder Consistency Analysis - Placeholder naming inconsistencies
  #   7. Implementation Analysis - Current state vs. specification
  #   8. Flow-to-YAML Mapping - Cross-reference between PDF flows and YAML keys
  #   9. Phase 2 Recommendations - Prioritized task list for corrections
  #   10. Pendientes / Fuera de Alcance - Out-of-scope flows (C2A)
  #
  # Usage:
  #   generator = ElisaAudit::AuditReportGenerator.new
  #   result = generator.call(
  #     yaml_inventory: yaml_inventory_result,
  #     ai_violations: violations_array,
  #     template_requirements: templates_array
  #   )
  #
  #   # Result is a hash with:
  #   # {
  #   #   markdown: "Full report content...",
  #   #   output_path: "/path/to/phase1-audit-report.md",
  #   #   stats: { total_messages: 50, violations: 10, templates: 7 }
  #   # }
  #
  # Requirements:
  #   - Req 1.6: Generate Phase 1 Audit Report
  #   - Req 19.5: Note C2A in audit report "Pendientes / fuera de alcance" section
  #   - Req 20.6: Generate Pre-Correction Implementation Analysis
  #   - Req 28.1: Generate Audit Report Executive Summary
  class AuditReportGenerator
    # Output path for the generated audit report
    OUTPUT_PATH = Rails.root.join('.kiro', 'specs', 'elisa-message-copy-verification', 'phase1-audit-report.md')

    # Initialize the generator
    def initialize
      @yaml_inventory = nil
      @ai_violations = []
      @template_requirements = []
    end

    # Main entry point - generates the complete audit report
    #
    # @param yaml_inventory [Hash] Result from YamlInventoryGenerator with :markdown, :entries, :stats
    # @param ai_violations [Array<AiUsageViolation>] Violations from AiUsageAnalyzer
    # @param template_requirements [Array<TemplateRequirement>] Requirements from WhatsAppTemplateDetector
    # @return [Hash] Result with markdown, output_path, and stats
    # @raise [ReportGenerationError] if report cannot be generated
    def call(yaml_inventory:, ai_violations:, template_requirements:)
      # Store inputs
      @yaml_inventory = yaml_inventory
      @ai_violations = ai_violations
      @template_requirements = template_requirements

      # Generate all report sections
      sections = []
      sections << generate_header
      sections << generate_executive_summary
      sections << generate_yaml_syntax_section
      sections << generate_comparison_template
      sections << generate_ai_violations_section
      sections << generate_templates_section
      sections << generate_placeholder_consistency_section
      sections << generate_implementation_analysis
      sections << generate_flow_to_yaml_mapping
      sections << generate_phase2_recommendations
      sections << generate_out_of_scope_section

      # Combine all sections
      markdown = sections.join("\n\n---\n\n")

      # Save to file
      output_path = save_to_file(markdown)

      # Calculate final stats
      stats = calculate_final_stats

      {
        markdown: markdown,
        output_path: output_path,
        stats: stats
      }
    rescue StandardError => e
      raise ReportGenerationError, "Failed to generate audit report: #{e.message}"
    end

    private

    # Generate report header with metadata
    # @return [String] Markdown header section
    def generate_header
      <<~MARKDOWN
        # Phase 1 Audit Report: Elisa Message Copy Verification

        **Generated:** #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}
        **Spec:** `.kiro/specs/elisa-message-copy-verification/`
        **Source of Truth:** `trato-flujos-v4-ux-copy.pdf` (50 flows: P1A-P20, C1A-C7D)

        ## Report Purpose

        This report documents the complete Phase 1 audit of all Elisa conversational messages, comparing
        current implementation in `elisa_es.yml` against the official UX copy specification and AI usage
        rules defined in `prompt-kiro-correccion-copys-ia.md`.

        The audit identifies:
        - Message copy discrepancies between YAML and PDF
        - AI usage violations (improper generation, missing extraction/interpretation)
        - WhatsApp Message Template requirements for proactive messages
        - Implementation gaps and readiness for Phase 2 corrections
      MARKDOWN
    end

    # Generate executive summary section with high-level statistics
    # Implements Requirement 28.1: Generate Audit Report Executive Summary
    #
    # @return [String] Markdown executive summary section
    def generate_executive_summary
      stats = @yaml_inventory[:stats]
      syntax_errors = @yaml_inventory[:syntax_errors] || []
      critical_violations = @ai_violations.count { |v| v.severity == :critical }
      moderate_violations = @ai_violations.count { |v| v.severity == :moderate }
      minor_violations = @ai_violations.count { |v| v.severity == :minor }

      # Count syntax errors by severity
      critical_syntax = syntax_errors.count { |e| e.severity == :critical }
      warning_syntax = syntax_errors.count { |e| e.severity == :warning }
      info_syntax = syntax_errors.count { |e| e.severity == :info }

      <<~MARKDOWN
        ## 1. Executive Summary

        ### Audit Statistics

        **Messages Inventory:**
        - **Total messages found:** #{stats[:total]}
        - **Provider messages (P1-P20):** #{stats[:provider]}
        - **Client messages (C1-C7):** #{stats[:client]}
        - **Unknown/unmapped:** #{stats[:unknown]}

        **YAML Syntax Validation:**
        - **Total syntax issues:** #{syntax_errors.count}
        - **🔴 Critical syntax errors:** #{critical_syntax}
        - **🟡 Warning syntax issues:** #{warning_syntax}
        - **🔵 Info syntax notes:** #{info_syntax}

        **AI Usage Analysis:**
        - **Total violations detected:** #{@ai_violations.count}
        - **🔴 Critical violations:** #{critical_violations}
        - **🟡 Moderate violations:** #{moderate_violations}
        - **🟢 Minor violations:** #{minor_violations}

        **WhatsApp Message Templates:**
        - **Total templates required:** #{@template_requirements.count}
        - **Proactive flows requiring approval:** #{AiUsageRules::PROACTIVE_TEMPLATES.count}
        - **Missing template messages:** #{@template_requirements.count { |t| t.yaml_key.include?('MISSING') }}

        ### Risk Assessment

        #{generate_risk_assessment(critical_violations, moderate_violations, minor_violations, critical_syntax)}

        ### Phase 2 Readiness

        #{generate_readiness_assessment(critical_syntax)}
      MARKDOWN
    end

    # Generate risk assessment based on violation counts
    # @param critical [Integer] Critical violation count
    # @param moderate [Integer] Moderate violation count
    # @param minor [Integer] Minor violation count
    # @param critical_syntax [Integer] Critical syntax error count
    # @return [String] Risk assessment text
    def generate_risk_assessment(critical, moderate, minor, critical_syntax)
      if critical_syntax > 0
        "**🔴 HIGH RISK:** #{critical_syntax} critical YAML syntax error(s) detected. These must be fixed " \
        "before running the application to avoid parse errors. #{critical > 0 ? "Additionally, #{critical} critical AI violation(s) require immediate attention." : ''}"
      elsif critical > 0
        "**🔴 HIGH RISK:** #{critical} critical violation(s) detected. These require immediate attention as they " \
        "involve AI generating messages that should be fixed templates (e.g., P10-P14 thank you message)."
      elsif moderate > 5
        "**🟡 MODERATE RISK:** #{moderate} moderate violation(s) detected. These involve AI usage mismatches " \
        "that need correction but are not critically breaking."
      elsif moderate > 0 || minor > 0
        "**🟢 LOW RISK:** Only minor/moderate violations detected. Implementation is mostly correct with " \
        "some adjustments needed."
      else
        "**✅ NO RISK:** No AI usage violations detected. Implementation matches specification."
      end
    end

    # Generate readiness assessment for Phase 2
    # @param critical_syntax [Integer] Critical syntax error count
    # @return [String] Readiness assessment text
    def generate_readiness_assessment(critical_syntax)
      prerequisites = []

      # Check for critical syntax errors
      prerequisites << "- ⚠️ Fix #{critical_syntax} critical YAML syntax errors" if critical_syntax > 0

      # Check for critical blockers
      critical_count = @ai_violations.count { |v| v.severity == :critical }
      prerequisites << "- ⚠️ Resolve #{critical_count} critical AI violations before proceeding" if critical_count > 0

      # Check for missing templates
      missing_templates = @template_requirements.count { |t| t.yaml_key.include?('MISSING') }
      prerequisites << "- ⚠️ Create #{missing_templates} missing message templates in elisa_es.yml" if missing_templates > 0

      # Check for manual comparison completion
      prerequisites << "- ⏳ Complete manual PDF comparison in Section 2 (Comparison Template)"

      if prerequisites.empty?
        "**Status:** ✅ Ready to proceed with Phase 2 corrections.\n\n" \
        "All prerequisites met. Review this report and proceed with systematic corrections."
      else
        "**Status:** ⏳ Prerequisites required before Phase 2.\n\n" \
        "#{prerequisites.join("\n")}\n\n" \
        "Complete these prerequisites before implementing Phase 2 corrections."
      end
    end

    # Generate YAML Syntax Validation section
    # Documents any pre-existing syntax errors found in elisa_es.yml
    # Implements Requirement 26.5: Document pre-existing syntax errors in audit report
    #
    # @return [String] Markdown YAML syntax section
    def generate_yaml_syntax_section
      syntax_errors = @yaml_inventory[:syntax_errors] || []

      if syntax_errors.empty?
        return <<~MARKDOWN
          ## 2. YAML Syntax Validation

          **✅ No syntax errors detected!**

          The YAML file `config/locales/elisa_es.yml` has been validated and no syntax issues were found:
          - ✅ Multiline message syntax is correct
          - ✅ Array syntax for List Message options is valid
          - ✅ Interpolation variables use correct Rails i18n syntax (%{var})
          - ✅ General YAML structure is valid

          The file is ready for Phase 2 corrections.
        MARKDOWN
      end

      # Count errors by type
      critical_errors = syntax_errors.count { |e| e.severity == :critical }
      warning_errors = syntax_errors.count { |e| e.severity == :warning }
      info_errors = syntax_errors.count { |e| e.severity == :info }

      section = <<~MARKDOWN
        ## 2. YAML Syntax Validation

        **⚠️ Syntax issues detected in `config/locales/elisa_es.yml`**

        The following pre-existing syntax issues were found during validation. These should be
        addressed before making Phase 2 corrections to avoid breaking changes.

        **Summary:**
        - **Total issues found:** #{syntax_errors.count}
        - **🔴 Critical errors:** #{critical_errors} (must fix immediately)
        - **🟡 Warnings:** #{warning_errors} (should fix)
        - **🔵 Info notes:** #{info_errors} (optional improvements)

        ### Validation Rules

        The validator checks for:
        1. **Interpolation Syntax:** Variables must use Rails i18n syntax `%{variable}`, not Liquid/Mustache `{{variable}}`
        2. **Multiline Strings:** Proper YAML string syntax with appropriate quoting for special characters
        3. **Array Syntax:** Valid YAML arrays for List Message options (title, body, button, options)
        4. **General Structure:** Parseable YAML with no syntax errors

      MARKDOWN

      # Group errors by severity
      if critical_errors > 0
        section += "\n### 🔴 Critical Errors (#{critical_errors})\n\n"
        section += "These errors will cause YAML parse failures and must be fixed immediately.\n\n"
        section += generate_syntax_errors_table(syntax_errors.select { |e| e.severity == :critical })
      end

      if warning_errors > 0
        section += "\n### 🟡 Warnings (#{warning_errors})\n\n"
        section += "These issues may cause problems and should be addressed.\n\n"
        section += generate_syntax_errors_table(syntax_errors.select { |e| e.severity == :warning })
      end

      if info_errors > 0
        section += "\n### 🔵 Info Notes (#{info_errors})\n\n"
        section += "These are suggestions for improvement.\n\n"
        section += generate_syntax_errors_table(syntax_errors.select { |e| e.severity == :info })
      end

      section
    end

    # Generate syntax errors table
    # @param errors [Array<YamlSyntaxValidator::ValidationError>] Syntax errors
    # @return [String] Markdown table
    def generate_syntax_errors_table(errors)
      return "_No errors in this category._\n" if errors.empty?

      table = []

      # Table header
      table << "| Tipo | Línea | Clave YAML | Mensaje |"
      table << "|------|-------|------------|---------|"

      # Sort by line number
      sorted_errors = errors.sort_by { |e| e.line_number || 0 }

      # Table rows
      sorted_errors.each do |error|
        type = error.error_type.to_s.capitalize
        line = error.line_number || 'N/A'
        key = error.key_path || '-'
        message = error.message.gsub('|', '\\|') # Escape pipes for markdown

        table << "| #{type} | #{line} | `#{key}` | #{message} |"
      end

      table.join("\n") + "\n"
    end

    # Generate manual comparison template section
    # Creates a structured template for developer to fill during PDF comparison
    # Implements Requirement 1.6: Document every discrepancy found
    #
    # @return [String] Markdown comparison template section
    def generate_comparison_template
      entries = @yaml_inventory[:entries]

      # Create comparison template header
      template = <<~MARKDOWN
        ## 3. Manual Comparison Template

        **Instructions:**
        This section provides a structured template for manual PDF comparison. For each message:
        1. Open `trato-flujos-v4-ux-copy.pdf`
        2. Locate the corresponding flow section
        3. Fill in the "PDF Text (Source of Truth)" column with exact copy from PDF
        4. Fill in the "Status" column: `✅ Match`, `❌ Mismatch`, `⚠️ Missing`, `⚠️ Extra`
        5. Add notes in the "Notes" column for context (character differences, punctuation, etc.)

        **Note:** C2A is out of scope (no copy defined in PDF). Mark as "Pendiente de definición".

        ### Provider Messages Comparison (P1A-P20)

      MARKDOWN

      # Provider messages table
      provider_entries = entries.select { |e| e.flow_id.to_s.start_with?('P') }
      template += generate_comparison_table(provider_entries)
      template += "\n\n"

      # Client messages table
      template += "### Client Messages Comparison (C1A-C7D)\n\n"
      client_entries = entries.select { |e| e.flow_id.to_s.start_with?('C') }
      template += generate_comparison_table(client_entries)

      template
    end

    # Generate comparison table for a set of entries
    # @param entries [Array<MessageEntry>] Message entries
    # @return [String] Markdown table
    def generate_comparison_table(entries)
      return "_No messages found._\n" if entries.empty?

      table = []

      # Table header
      table << "| Flow ID | YAML Key | Current Text | PDF Text (Source of Truth) | Status | Notes |"
      table << "|---------|----------|--------------|----------------------------|--------|-------|"

      # Sort entries by flow ID
      sorted_entries = entries.sort_by { |e| [e.flow_id.to_s, e.line_number || 0] }

      # Table rows
      sorted_entries.each do |entry|
        # Truncate long messages for readability
        current_text = truncate_message(entry.content, 40)

        table << "| #{entry.flow_id} | `#{entry.yaml_key}` | #{current_text} | _[TO FILL]_ | _[TO FILL]_ | _[TO FILL]_ |"
      end

      table.join("\n")
    end

    # Generate AI violations section
    # Lists all detected violations grouped by severity
    # Implements Requirement 2.4: List all improperly LLM-generated messages
    #
    # @return [String] Markdown AI violations section
    def generate_ai_violations_section
      return generate_no_violations_message if @ai_violations.empty?

      section = <<~MARKDOWN
        ## 4. AI Usage Violations

        This section documents all violations where AI usage does not match the specification
        defined in `prompt-kiro-correccion-copys-ia.md` (AI_Usage_Rules).

        **Total Violations:** #{@ai_violations.count}

      MARKDOWN

      # Group violations by severity
      critical = @ai_violations.select { |v| v.severity == :critical }
      moderate = @ai_violations.select { |v| v.severity == :moderate }
      minor = @ai_violations.select { |v| v.severity == :minor }

      # Critical violations
      if critical.any?
        section += "\n### 🔴 Critical Violations (#{critical.count})\n\n"
        section += "These violations must be fixed immediately. They involve AI generating messages " \
                   "that should be 100% fixed templates.\n\n"
        section += generate_violations_table(critical)
      end

      # Moderate violations
      if moderate.any?
        section += "\n### 🟡 Moderate Violations (#{moderate.count})\n\n"
        section += "These violations involve AI usage mismatches that need correction.\n\n"
        section += generate_violations_table(moderate)
      end

      # Minor violations
      if minor.any?
        section += "\n### 🟢 Minor Violations (#{minor.count})\n\n"
        section += "These violations involve wrong model assignments (Haiku vs. Sonnet).\n\n"
        section += generate_violations_table(minor)
      end

      section
    end

    # Generate message when no violations are found
    # @return [String] Markdown message
    def generate_no_violations_message
      <<~MARKDOWN
        ## 4. AI Usage Violations

        **✅ No violations detected!**

        All AI usage matches the specification defined in `prompt-kiro-correccion-copys-ia.md`.
        No corrections needed for AI implementation.
      MARKDOWN
    end

    # Generate violations table
    # Implements Requirement 2.4, 2.5, 3.6, 20.2
    # Includes cross-references to AI_Usage_Rules documentation
    #
    # @param violations [Array<AiUsageViolation>] Violations to display
    # @return [String] Markdown table with AI_Usage_Rules references
    def generate_violations_table(violations)
      table = []

      # Table header - Added "AI Rules Reference" column
      table << "| Flow ID | Type | File | Line | Method | Current Implementation | Expected Implementation | AI Rules Reference |"
      table << "|---------|------|------|------|--------|------------------------|-------------------------|--------------------|"

      # Table rows
      violations.each do |violation|
        file_path = shorten_file_path(violation.file_path)
        current_impl = truncate_message(violation.current_impl, 40)
        expected_impl = truncate_message(violation.expected_impl, 40)

        # Get AI_Usage_Rules reference for this flow
        ai_rules_ref = generate_ai_rules_reference(violation.flow_id)

        table << "| #{violation.flow_id} | #{violation.type_label} | `#{file_path}` | #{violation.line_number} | `#{violation.method_name}` | #{current_impl} | #{expected_impl} | #{ai_rules_ref} |"
      end

      table.join("\n") + "\n\n" + generate_ai_rules_legend
    end

    # Generate AI_Usage_Rules reference for a flow
    # Creates a formatted reference showing the flow's configuration in AiUsageRules::FLOWS
    #
    # @param flow_id [String] Flow identifier
    # @return [String] Formatted reference with type, model, and status
    def generate_ai_rules_reference(flow_id)
      config = AiUsageRules.expected_for_flow(flow_id)

      # Handle unknown/undocumented flows
      return "⚠️ Not documented" if config[:type] == :unknown || config[:status] == :undocumented

      # Build reference with type, model (if present), and status
      parts = []
      parts << "Type: `#{config[:type]}`"
      parts << "Model: `#{config[:model]}`" if config[:model]
      parts << "Status: `#{config[:status]}`"

      parts.join("<br/>")
    end

    # Generate legend explaining AI_Usage_Rules references
    # @return [String] Markdown legend section
    def generate_ai_rules_legend
      <<~MARKDOWN
        **AI_Usage_Rules Reference Legend:**
        - **Type**: Flow classification (fixed_template, extraction, generation, interpretation, etc.)
        - **Model**: Required Claude model (:haiku or :sonnet)
        - **Status**: Implementation status (correct, verify, critical_verify, implement, undocumented)

        See `app/services/elisa_audit/ai_usage_rules.rb` for complete flow definitions and documentation.
        See `prompt-kiro-correccion-copys-ia.md` for original specification.
      MARKDOWN
    end

    # Generate WhatsApp templates section
    # Lists all required templates for Meta approval
    # Implements Requirement 4.1-4.7 and 18.1-18.6
    #
    # @return [String] Markdown templates section
    def generate_templates_section
      section = <<~MARKDOWN
        ## 5. WhatsApp Message Templates

        This section documents all proactive messages requiring WhatsApp Message Templates
        for Meta approval. These messages are sent outside the 24-hour customer service window.

        **Total Templates Required:** #{@template_requirements.count}
        **Proactive Flows:** #{AiUsageRules::PROACTIVE_TEMPLATES.join(', ')}

        ### Template Requirements for Meta Registration

      MARKDOWN

      # Group templates by flow
      @template_requirements.group_by(&:flow_id).each do |flow_id, requirements|
        section += "\n#### Flow #{flow_id}\n\n"

        requirements.each_with_index do |req, index|
          section += generate_template_card(req, index + 1)
        end
      end

      # Add submission guidance
      section += <<~MARKDOWN

        ### Meta Submission Guidance

        1. **Template Category:** All templates listed above are `UTILITY` category (transactional messages)
        2. **Template Language:** Spanish (es)
        3. **Template Variables:** Use double curly braces `{{variable_name}}` syntax
        4. **Approval Process:** Submit templates via WhatsApp Business API Manager
        5. **Testing:** Templates must be approved before use in production

        **Next Steps:**
        - Create missing messages in `elisa_es.yml` (marked as MISSING)
        - Prepare template registration forms with exact text and variables
        - Submit templates for Meta approval
        - Store approved template IDs in Rails configuration
      MARKDOWN

      section
    end

    # Generate individual template card
    # @param requirement [TemplateRequirement] Template requirement
    # @param number [Integer] Template number within flow
    # @return [String] Markdown template card
    def generate_template_card(requirement, number)
      missing_badge = requirement.yaml_key.include?('MISSING') ? ' ⚠️ _MISSING_' : ''

      <<~MARKDOWN
        **Template #{number}: `#{requirement.template_name}`**#{missing_badge}

        - **Category:** #{requirement.category_badge}
        - **Proactive:** #{requirement.is_proactive ? '✅ Yes (requires approval)' : '❌ No'}
        - **YAML Key:** `#{requirement.yaml_key}`

        **Message Text:**
        ```
        #{requirement.message_text}
        ```

        **Variables:**
        #{requirement.formatted_variables}

      MARKDOWN
    end

    # Generate placeholder consistency analysis section
    # Analyzes all messages for placeholder naming inconsistencies
    # Implements Requirement 30: Verify Message Placeholder Consistency
    #
    # This section scans all messages for placeholder names and identifies inconsistencies
    # in naming conventions across flows. Provides recommendations for standardization.
    #
    # Requirements: 30.1, 30.2, 30.3, 30.4, 30.5, 30.6
    #
    # @return [String] Markdown placeholder analysis section
    def generate_placeholder_consistency_section
      # Get message entries from yaml inventory
      entries = @yaml_inventory[:entries]

      # Create and run the placeholder consistency analyzer
      analyzer = PlaceholderConsistencyAnalyzer.new(entries)
      result = analyzer.call

      # Generate the report section from analyzer
      report = analyzer.generate_markdown_report

      # The analyzer already includes "## Placeholder Consistency Analysis" header
      # We just need to update it to be section 5
      section_header = report.lines.first.strip.sub(/^## /, '## 5. ')

      # Build complete section
      section = section_header + "\n\n"

      # Add the rest of the analyzer report (skip first two lines - header and blank line)
      section += report.lines[2..].join

      section
    end

    # Generate implementation analysis section
    # Analyzes current state vs. specification for each flow
    # Implements Requirement 20.6: Generate Pre-Correction Implementation Analysis
    #
    # This section documents:
    # - Current implementation status for each flow
    # - Classification: correct, needs implementation, needs fix
    # - File and line references for AI usage points
    # - Model assignments (Haiku/Sonnet) to preserve
    #
    # Requirements: 20.1, 20.2, 20.3, 27.2, 27.5
    #
    # @return [String] Markdown implementation analysis section
    def generate_implementation_analysis
      section = <<~MARKDOWN
        ## 6. Implementation Analysis

        This section analyzes the current implementation status for each flow that involves AI usage,
        cross-referencing against AI_Usage_Rules specification. It includes file and line references
        for each AI usage point detected in the codebase.

        ### Flow Status Summary

      MARKDOWN

      # Get all flows from AI_Usage_Rules
      flows = AiUsageRules::FLOWS

      # Group by status
      correct_flows = flows.select { |_id, config| config[:status] == :correct }
      verify_flows = flows.select { |_id, config| config[:status] == :verify }
      critical_verify_flows = flows.select { |_id, config| config[:status] == :critical_verify }
      implement_flows = flows.select { |_id, config| config[:status] == :implement }
      undocumented_flows = flows.select { |_id, config| config[:status] == :undocumented }

      # Correct flows - do not touch
      section += "\n#### ✅ Correct Flows (#{correct_flows.count}) - Do Not Touch\n\n"
      section += "These flows are implemented correctly per specification. **Do not modify.**\n\n"
      section += generate_flow_implementation_details(correct_flows)

      # Verify flows - need verification
      section += "\n#### ⏳ Verify Flows (#{verify_flows.count}) - Need Verification\n\n"
      section += "These flows require verification during audit. Check implementation matches specification.\n\n"
      section += generate_flow_implementation_details(verify_flows)

      # Critical verify flows - must be fixed templates
      section += "\n#### 🔴 Critical Verify Flows (#{critical_verify_flows.count}) - Critical Check Required\n\n"
      section += "These flows require critical verification. Must be 100% fixed templates with NO AI generation.\n\n"
      section += generate_flow_implementation_details(critical_verify_flows)

      # Implement flows - AI missing
      section += "\n#### 🚧 Implement Flows (#{implement_flows.count}) - AI Missing, Needs Implementation\n\n"
      section += "These flows need new AI implementation (not yet implemented).\n\n"
      section += generate_flow_implementation_details(implement_flows)

      # Undocumented flows
      if undocumented_flows.any?
        section += "\n#### ❓ Undocumented Flows (#{undocumented_flows.count}) - Manual Review Required\n\n"
        section += "These flows are not documented in AI_Usage_Rules. Manual review required.\n\n"
        section += generate_flow_implementation_details(undocumented_flows)
      end

      # Add model assignments summary
      section += generate_model_assignments_summary

      section
    end

    # Generate detailed flow implementation information with file/line references
    # Implements Requirement 20.3: List file and line references for each AI usage point
    #
    # @param flows [Hash] Flows hash (flow_id => config)
    # @return [String] Markdown list with implementation details
    def generate_flow_implementation_details(flows)
      return "_None_\n" if flows.empty?

      list = []
      flows.each do |flow_id, config|
        # Basic flow information
        model_badge = config[:model] ? " [`#{config[:model]}`]" : ""
        flow_line = "- **#{flow_id}** (#{config[:type]})#{model_badge}: #{config[:note]}"

        # Find violations related to this flow to get file/line references
        related_violations = @ai_violations.select { |v| v.flow_id == flow_id }

        if related_violations.any?
          # Add file/line references from violations
          flow_line += "\n  - **Implementation references:**"
          related_violations.each do |violation|
            file_ref = shorten_file_path(violation.file_path)
            flow_line += "\n    - `#{file_ref}:#{violation.line_number}` in `#{violation.method_name}`"
          end
        elsif config[:model]
          # For flows with AI usage but no violations, add a note
          flow_line += "\n  - _Implementation uses AI as specified, no violations detected_"
        end

        list << flow_line
      end

      list.join("\n") + "\n"
    end

    # Generate model assignments summary to document which flows use Haiku vs Sonnet
    # Implements Requirement 27.5: Document Haiku/Sonnet model assignments to preserve
    #
    # @return [String] Markdown model assignments section
    def generate_model_assignments_summary
      haiku_flows = AiUsageRules.flows_by_model(:haiku)
      sonnet_flows = AiUsageRules.flows_by_model(:sonnet)

      <<~MARKDOWN

        ### Model Assignments (MUST PRESERVE)

        **IMPORTANT:** The following model assignments must be preserved during all corrections.
        Do not change Haiku to Sonnet or vice versa unless explicitly documented in AI_Usage_Rules.

        **Haiku Flows (#{haiku_flows.count}):**
        #{haiku_flows.sort.join(', ')}

        **Sonnet Flows (#{sonnet_flows.count}):**
        #{sonnet_flows.sort.join(', ')}

        **Rationale:**
        - **Haiku** is used for extraction, interpretation, and simpler generation tasks (faster, lower cost)
        - **Sonnet** is used for complex generation requiring better quality (provider bio generation)
      MARKDOWN
    end

    # Generate Flow-to-YAML Mapping section
    # Creates comprehensive mapping table showing each PDF flow ID to its corresponding YAML key with status
    # Implements Requirement 29: Cross-Reference PDF Flows with YAML Keys
    #
    # This section provides a complete reference mapping between:
    # - Flow IDs from PDF (P1A-P20, C1A-C7D)
    # - YAML keys in elisa_es.yml
    # - Status indicators (matches, discrepancy, missing, extra, AI violation)
    # - YAML line numbers for quick navigation
    # - PDF page references (to be filled manually)
    #
    # Requirements: 29.1, 29.2, 29.3, 29.4, 29.5, 29.6
    #
    # @return [String] Markdown mapping section
    def generate_flow_to_yaml_mapping
      section = <<~MARKDOWN
        ## 7. Flow-to-YAML Mapping

        This section provides a comprehensive mapping table showing each PDF flow ID to its corresponding
        YAML key(s) with status indicators. Use this as a quick reference for navigating between the PDF
        specification and the YAML implementation.

        **Status Legend:**
        - ✅ **Matches**: YAML message exists and matches PDF (to be verified in manual comparison)
        - ❌ **Discrepancy**: YAML message exists but differs from PDF (to be verified in manual comparison)
        - ⚠️ **Missing**: Flow exists in PDF but no corresponding YAML key found
        - ⚠️ **Extra**: YAML key exists but no corresponding flow in PDF
        - 🔴 **AI Violation**: Flow has AI usage violation detected in Section 3

        **Note:** Status for message accuracy will be determined during manual PDF comparison (Section 2).
        AI violations are marked based on Section 3 analysis.

      MARKDOWN

      # Generate provider flows mapping
      section += "\n### Provider Flows (P1A-P20)\n\n"
      section += generate_flow_mapping_table(provider_flow_ids)

      # Generate client flows mapping
      section += "\n### Client Flows (C1A-C7D)\n\n"
      section += generate_flow_mapping_table(client_flow_ids)

      # Add navigation help
      section += <<~MARKDOWN

        ### Using This Mapping

        **For PDF → YAML navigation:**
        1. Find the flow ID in the table above (e.g., P6A)
        2. Note the YAML key (e.g., `elisa.provider.bio_generation.processing`)
        3. Open `config/locales/elisa_es.yml` and go to the line number shown
        4. Review or edit the message content

        **For YAML → PDF navigation:**
        1. Find the YAML key in your editor
        2. Search for the YAML key in the table above
        3. Note the flow ID (e.g., P6A)
        4. Open `trato-flujos-v4-ux-copy.pdf` and find the flow section
        5. Compare the message text

        **For AI violation investigation:**
        1. Look for 🔴 **AI Violation** markers in the Status column
        2. Cross-reference with Section 3 (AI Usage Violations) for details
        3. Review the file and line references in Section 3
        4. Plan fixes according to Section 6 (Phase 2 Recommendations)
      MARKDOWN

      section
    end

    # Generate flow mapping table for a list of flow IDs
    # @param flow_ids [Array<String>] List of flow IDs to include in the table
    # @return [String] Markdown table with mapping information
    def generate_flow_mapping_table(flow_ids)
      return "_No flows found._\n" if flow_ids.empty?

      table = []

      # Table header
      table << "| Flow ID | YAML Key | Line | Status | AI Type | PDF Page | Notes |"
      table << "|---------|----------|------|--------|---------|----------|-------|"

      # Generate rows for each flow
      flow_ids.each do |flow_id|
        # Find all YAML entries for this flow
        entries = find_yaml_entries_for_flow(flow_id)

        if entries.empty?
          # Flow defined but no YAML entries found
          table << generate_missing_flow_row(flow_id)
        else
          # Flow has YAML entries - generate row for each
          entries.each_with_index do |entry, index|
            table << generate_flow_mapping_row(flow_id, entry, index)
          end
        end
      end

      table.join("\n") + "\n"
    end

    # Generate mapping row for a flow with YAML entry
    # @param flow_id [String] Flow identifier
    # @param entry [MessageEntry] YAML message entry
    # @param index [Integer] Index of this entry within the flow (for flows with multiple messages)
    # @return [String] Markdown table row
    def generate_flow_mapping_row(flow_id, entry, index)
      # Determine status
      status = determine_flow_status(flow_id, entry)

      # Get AI type from AiUsageRules
      ai_config = AiUsageRules.expected_for_flow(flow_id)
      ai_type = format_ai_type(ai_config[:type])

      # Format flow ID (show only on first row if multiple messages)
      flow_id_display = index.zero? ? "**#{flow_id}**" : ""

      # PDF page reference (to be filled manually)
      pdf_page = "_[TO FILL]_"

      # Notes (add AI model if present)
      notes = []
      notes << "Model: `#{ai_config[:model]}`" if ai_config[:model]
      notes << "Proactive" if AiUsageRules.proactive?(flow_id)
      notes_display = notes.any? ? notes.join(", ") : "-"

      "| #{flow_id_display} | `#{entry.yaml_key}` | #{entry.line_number || '-'} | #{status} | #{ai_type} | #{pdf_page} | #{notes_display} |"
    end

    # Generate row for a flow that has no YAML entries
    # @param flow_id [String] Flow identifier
    # @return [String] Markdown table row
    def generate_missing_flow_row(flow_id)
      # Get AI type from AiUsageRules
      ai_config = AiUsageRules.expected_for_flow(flow_id)
      ai_type = format_ai_type(ai_config[:type])

      # Special handling for C2A (documented as pending)
      if flow_id == 'C2A'
        return "| **#{flow_id}** | _N/A_ | - | 📋 **Pendiente** | #{ai_type} | _[TO FILL]_ | No copy defined in PDF |"
      end

      # Check for AI violation even for missing flows
      status = determine_flow_status(flow_id, nil)

      # Build notes
      notes = []
      notes << "Model: `#{ai_config[:model]}`" if ai_config[:model]
      notes << "Proactive" if AiUsageRules.proactive?(flow_id)
      notes << "No YAML key found for this flow"
      notes_display = notes.join(", ")

      # Missing YAML entry
      "| **#{flow_id}** | _[MISSING]_ | - | #{status} | #{ai_type} | _[TO FILL]_ | #{notes_display} |"
    end

    # Determine the status of a flow based on violations and YAML presence
    # @param flow_id [String] Flow identifier
    # @param entry [MessageEntry, nil] YAML message entry (nil for missing flows)
    # @return [String] Status indicator with emoji
    def determine_flow_status(flow_id, entry)
      # Check if flow has AI violation
      has_violation = @ai_violations.any? { |v| v.flow_id == flow_id }

      if has_violation
        violation = @ai_violations.find { |v| v.flow_id == flow_id }
        return "🔴 **AI Violation** (#{violation.severity_label})"
      end

      # For missing flows without violations
      return "⚠️ **Missing**" if entry.nil?

      # For flows with YAML entries but without violations, status depends on manual comparison
      # This will be filled during manual PDF comparison in Section 2
      "⏳ **To Verify**"
    end

    # Format AI type for display
    # @param ai_type [Symbol] AI type from AiUsageRules
    # @return [String] Formatted AI type with emoji
    def format_ai_type(ai_type)
      case ai_type
      when :fixed_template then "📄 Fixed"
      when :extraction then "📥 Extraction"
      when :generation then "🤖 Generation"
      when :generation_closing then "🤖 Gen (closing)"
      when :generation_summary then "🤖 Gen (summary)"
      when :interpretation then "🧠 Interpretation"
      when :interpretation_photos then "🧠 Int (photos)"
      when :tagging then "🏷️ Tagging"
      when :detection_semantic then "🔍 Detection"
      when :unknown then "❓ Unknown"
      when :undocumented then "❓ Undocumented"
      else "❓ Unknown"
      end
    end

    # Find all YAML entries that belong to a specific flow
    # Uses pattern matching on YAML keys to infer flow association
    # @param flow_id [String] Flow identifier (e.g., 'P6A', 'C4B')
    # @return [Array<MessageEntry>] Matching YAML entries
    def find_yaml_entries_for_flow(flow_id)
      return [] unless @yaml_inventory && @yaml_inventory[:entries]

      entries = @yaml_inventory[:entries]

      # Filter entries by flow_id (flow_id was inferred during inventory generation)
      entries.select { |entry| entry.flow_id.to_s == flow_id.to_s }
    end

    # Get all provider flow IDs from AiUsageRules
    # @return [Array<String>] Sorted array of provider flow IDs (P1A-P20)
    def provider_flow_ids
      AiUsageRules::FLOWS.keys.select { |flow_id| flow_id.start_with?('P') }.sort_by do |flow_id|
        # Sort by numeric part and alphabetic suffix
        match = flow_id.match(/P(\d+)([A-Z]*)/)
        [match[1].to_i, match[2]]
      end
    end

    # Get all client flow IDs from AiUsageRules
    # @return [Array<String>] Sorted array of client flow IDs (C1A-C7D)
    def client_flow_ids
      AiUsageRules::FLOWS.keys.select { |flow_id| flow_id.start_with?('C') }.sort_by do |flow_id|
        # Sort by numeric part and alphabetic suffix
        match = flow_id.match(/C(\d+)([A-Z]*)/)
        [match[1].to_i, match[2]]
      end
    end

    # Generate Phase 2 recommendations section
    # Provides prioritized task list for corrections with detailed file paths and flow IDs
    # Implements Requirement 24.1-24.5: Generate Phase 2 Correction Task List
    #
    # This method generates a prioritized, categorized task list where:
    # - Critical violations are listed first (Req 24.1)
    # - Tasks are grouped by category: message corrections, AI implementation changes, template preparation (Req 24.2)
    # - Each task has complexity estimate: simple, moderate, complex (Req 24.3)
    # - File paths and flow IDs are included for each task (Req 24.4)
    #
    # @return [String] Markdown recommendations section
    def generate_phase2_recommendations
      section = <<~MARKDOWN
        ## 8. Phase 2 Task Recommendations

        This section provides a prioritized, categorized task list for implementing corrections identified in this audit.
        Each task includes specific file paths, flow IDs, and complexity estimates.

        ### Prioritization Strategy

        1. **🔴 Critical violations** - Fix improper AI generation (especially P10-P14) - MUST FIX FIRST
        2. **🟡 Message corrections** - Update message copies to match PDF source of truth
        3. **🟡 AI implementation changes** - Fix AI usage mismatches and missing implementations
        4. **🟢 Template preparation** - Prepare WhatsApp templates for Meta approval

        ### Task Categories

      MARKDOWN

      # Category 1: Critical AI Implementation Changes (highest priority)
      critical_violations = @ai_violations.select { |v| v.severity == :critical }
      if critical_violations.any?
        section += generate_critical_ai_tasks(critical_violations)
      end

      # Category 2: Message Corrections (high priority)
      missing_templates = @template_requirements.select { |t| t.yaml_key.include?('MISSING') }
      section += generate_message_correction_tasks(missing_templates)

      # Category 3: Moderate AI Implementation Changes (medium priority)
      moderate_violations = @ai_violations.select { |v| v.severity == :moderate }
      if moderate_violations.any?
        section += generate_moderate_ai_tasks(moderate_violations)
      end

      # Category 4: Minor AI Implementation Changes (low priority)
      minor_violations = @ai_violations.select { |v| v.severity == :minor }
      if minor_violations.any?
        section += generate_minor_ai_tasks(minor_violations)
      end

      # Category 5: Template Preparation (lowest priority, depends on external process)
      section += generate_template_preparation_tasks

      # Add summary
      section += generate_phase2_summary

      section
    end

    # Generate critical AI implementation tasks (Category 1)
    # These are MUST-FIX violations where AI is generating messages that should be fixed templates
    #
    # @param violations [Array<AiUsageViolation>] Critical violations
    # @return [String] Markdown section
    def generate_critical_ai_tasks(violations)
      section = <<~MARKDOWN
        #### Category 1: Critical AI Implementation Changes (Priority: 🔴 CRITICAL)

        **Complexity:** Complex (requires understanding of AI usage patterns and service architecture)
        **Affected Flows:** #{violations.map(&:flow_id).uniq.sort.join(', ')}
        **Files to Modify:** #{violations.map(&:file_path).uniq.count} file(s)

        These violations involve AI generating user-facing messages that MUST be fixed templates per specification.
        This is the highest priority category as it directly violates the core principle: "Fixed copies = static templates".

        **Tasks:**

      MARKDOWN

      # Group by flow ID for better organization
      violations.group_by(&:flow_id).sort.each do |flow_id, flow_violations|
        section += "\n**Flow #{flow_id}:**\n\n"

        flow_violations.each do |violation|
          file_ref = shorten_file_path(violation.file_path)
          section += <<~TASK
            - [ ] **Fix improper AI generation in `#{file_ref}:#{violation.line_number}`**
              - **Method:** `#{violation.method_name}`
              - **Current:** #{violation.current_impl}
              - **Expected:** #{violation.expected_impl}
              - **Action:** Convert AI generation to fixed template from `elisa_es.yml`

          TASK
        end
      end

      section += "\n**Estimated Time:** 2-4 hours (analysis + implementation + testing)\n\n"
      section
    end

    # Generate message correction tasks (Category 2)
    # These are text updates in elisa_es.yml to match PDF specification
    #
    # @param missing_templates [Array<TemplateRequirement>] Missing template requirements
    # @return [String] Markdown section
    def generate_message_correction_tasks(missing_templates)
      section = <<~MARKDOWN
        #### Category 2: Message Corrections (Priority: 🟡 HIGH)

        **Complexity:** Simple (text updates in YAML file)
        **Files to Modify:** `config/locales/elisa_es.yml`

        These tasks involve updating message text in `elisa_es.yml` to match the PDF source of truth.
        Includes both corrections to existing messages and creation of missing templates.

        **Tasks:**

      MARKDOWN

      # Task 2.1: Create missing templates
      if missing_templates.any?
        section += "\n**2.1 Create Missing Message Templates**\n\n"
        section += "_These message keys are referenced in the code but don't exist in elisa_es.yml:_\n\n"

        missing_templates.each do |template|
          yaml_key_clean = template.yaml_key.gsub(' (MISSING - needs to be created)', '')
          section += <<~TASK
            - [ ] Create `#{yaml_key_clean}` for flow **#{template.flow_id}**
              - **Message text:** See Section 4 (WhatsApp Templates) for exact copy
              - **Variables:** #{template.formatted_variables.split("\n").join(', ')}

          TASK
        end

        section += "\n"
      end

      # Task 2.2: Complete manual comparison
      section += <<~TASK
        **2.2 Complete Manual PDF Comparison**

        - [ ] **Fill Section 2 comparison template** by reading `trato-flujos-v4-ux-copy.pdf`
          - Read each flow section in PDF (P1A-P20, C1A-C7D)
          - Compare exact text with current YAML messages
          - Document discrepancies: text differences, punctuation, emojis, wording
          - Mark status: ✅ Match, ❌ Mismatch, ⚠️ Missing, ⚠️ Extra

      TASK

      # Task 2.3: Apply message corrections
      section += <<~TASK
        **2.3 Apply Message Corrections**

        - [ ] **Update all mismatched messages** in `config/locales/elisa_es.yml`
          - Preserve interpolation variables (%{name}, %{ciudad}, etc.)
          - Preserve YAML structure (multiline strings, arrays)
          - Fix character-level differences (punctuation, accents, emojis)
          - Validate YAML syntax after changes: `bundle exec rake i18n:check`

      TASK

      section += "\n**Estimated Time:** 3-5 hours (manual comparison 2-3h + corrections 1-2h)\n\n"
      section
    end

    # Generate moderate AI implementation tasks (Category 3)
    # These are AI usage mismatches that need correction but are not critically breaking
    #
    # @param violations [Array<AiUsageViolation>] Moderate violations
    # @return [String] Markdown section
    def generate_moderate_ai_tasks(violations)
      section = <<~MARKDOWN
        #### Category 3: Moderate AI Implementation Changes (Priority: 🟢 MEDIUM)

        **Complexity:** Moderate (requires service logic changes)
        **Affected Flows:** #{violations.map(&:flow_id).uniq.sort.join(', ')}
        **Files to Modify:** #{violations.map(&:file_path).uniq.count} file(s)

        These violations involve missing AI extraction/interpretation or improper AI usage patterns.
        They don't break core functionality but need correction for spec compliance.

        **Tasks:**

      MARKDOWN

      # Group by flow ID
      violations.group_by(&:flow_id).sort.each do |flow_id, flow_violations|
        section += "\n**Flow #{flow_id}:**\n\n"

        flow_violations.each do |violation|
          file_ref = shorten_file_path(violation.file_path)
          section += <<~TASK
            - [ ] **Fix AI usage in `#{file_ref}:#{violation.line_number}`**
              - **Method:** `#{violation.method_name}`
              - **Issue:** #{violation.current_impl}
              - **Fix:** #{violation.expected_impl}
              - **Type:** #{violation.type_label}

          TASK
        end
      end

      section += "\n**Estimated Time:** 2-3 hours (implementation + testing)\n\n"
      section
    end

    # Generate minor AI implementation tasks (Category 4)
    # These are wrong model assignments (Haiku vs Sonnet) - simple parameter updates
    #
    # @param violations [Array<AiUsageViolation>] Minor violations
    # @return [String] Markdown section
    def generate_minor_ai_tasks(violations)
      section = <<~MARKDOWN
        #### Category 4: Minor AI Implementation Changes (Priority: 🟢 LOW)

        **Complexity:** Simple (parameter updates only)
        **Affected Flows:** #{violations.map(&:flow_id).uniq.sort.join(', ')}
        **Files to Modify:** #{violations.map(&:file_path).uniq.count} file(s)

        These violations involve incorrect model assignments (Haiku vs Sonnet).
        Simple one-line fixes to update model parameter.

        **Tasks:**

      MARKDOWN

      violations.each do |violation|
        file_ref = shorten_file_path(violation.file_path)
        expected_model = AiUsageRules.expected_for_flow(violation.flow_id)[:model]

        section += <<~TASK
          - [ ] **Update model assignment in `#{file_ref}:#{violation.line_number}`**
            - **Flow:** #{violation.flow_id}
            - **Method:** `#{violation.method_name}`
            - **Current model:** `:#{violation.model_used}`
            - **Expected model:** `:#{expected_model}`
            - **Action:** Change `model: :#{violation.model_used}` to `model: :#{expected_model}`

        TASK
      end

      section += "\n**Estimated Time:** 30 minutes - 1 hour (simple parameter updates)\n\n"
      section
    end

    # Generate template preparation tasks (Category 5)
    # These involve external Meta approval process - lowest priority
    #
    # @return [String] Markdown section
    def generate_template_preparation_tasks
      proactive_count = @template_requirements.count { |t| t.is_proactive }

      <<~MARKDOWN
        #### Category 5: Template Preparation (Priority: 🟢 LOW)

        **Complexity:** Moderate (external approval process with Meta)
        **Affected Flows:** #{AiUsageRules::PROACTIVE_TEMPLATES.join(', ')}
        **Templates Required:** #{proactive_count} proactive template(s)

        These tasks involve preparing WhatsApp Message Templates for Meta approval.
        This can be done in parallel with other corrections but depends on external approval (1-3 business days).

        **Tasks:**

        - [ ] **Format templates for Meta submission**
          - Use exact message text from Section 4 (WhatsApp Message Templates)
          - Convert Ruby interpolation `%{var}` to WhatsApp syntax `{{var}}`
          - Prepare variable type definitions for each template
          - See Section 4 for complete template specifications

        - [ ] **Submit templates via WhatsApp Business API Manager**
          - Category: UTILITY (transactional messages)
          - Language: Spanish (es)
          - Upload each template with exact text and variables
          - Wait for Meta approval (typically 1-3 business days)

        - [ ] **Store approved template IDs in Rails configuration**
          - Add template IDs to `config/whatsapp_templates.yml` or environment variables
          - Map flow IDs to template IDs for service lookup
          - Document template names for future reference

        - [ ] **Update services to use template IDs**
          - **Files:** `app/services/provider_conversation_handler.rb`, `app/services/client_assistant_orchestrator.rb`
          - Modify proactive message sending to use `WhatsAppService.send_template`
          - Pass template ID and variable values
          - Remove any hardcoded message text for proactive flows

        **Estimated Time:** 4-6 hours (preparation 2h + submission 1h + implementation 2-3h) + 1-3 business days for Meta approval

      MARKDOWN
    end

    # Generate Phase 2 summary with total estimates and prerequisites
    #
    # @return [String] Markdown section
    def generate_phase2_summary
      critical_count = @ai_violations.count { |v| v.severity == :critical }
      moderate_count = @ai_violations.count { |v| v.severity == :moderate }
      minor_count = @ai_violations.count { |v| v.severity == :minor }
      missing_count = @template_requirements.count { |t| t.yaml_key.include?('MISSING') }

      <<~MARKDOWN

        ### Summary

        **Total Tasks by Category:**
        - 🔴 Critical AI changes: #{critical_count}
        - 🟡 Message corrections: #{missing_count + 2} (#{missing_count} missing + comparison + updates)
        - 🟢 Moderate AI changes: #{moderate_count}
        - 🟢 Minor AI changes: #{minor_count}
        - 🟢 Template preparation: 4

        **Estimated Total Effort:**
        - Critical AI fixes: 2-4 hours
        - Message corrections: 3-5 hours (including manual comparison)
        - Moderate AI fixes: 2-3 hours
        - Minor AI fixes: 0.5-1 hour
        - Template preparation: 4-6 hours (+ 1-3 days Meta approval)
        - **Total development time:** 12-19 hours
        - **Total calendar time:** 2-4 days (including Meta approval)

        ### Prerequisites Before Starting Phase 2

        - [ ] Review this audit report with technical team
        - [ ] Review this audit report with UX/product team (message copy changes)
        - [ ] Get approval for critical violation fixes (AI to static template changes)
        - [ ] Allocate 2-4 days for implementation + testing + Meta approval
        - [ ] Prepare test strategy for message changes (manual testing recommended)
        - [ ] Plan deployment strategy (staging → production with monitoring)

        ### Recommended Implementation Order

        1. **Day 1 Morning:** Fix critical AI violations (Category 1) - 2-4 hours
        2. **Day 1 Afternoon:** Complete manual PDF comparison (Category 2, Task 2.2) - 2-3 hours
        3. **Day 2 Morning:** Create missing templates + apply corrections (Category 2, Tasks 2.1 & 2.3) - 2-3 hours
        4. **Day 2 Afternoon:** Submit templates to Meta (Category 5, Tasks 1-2) - 1-2 hours
        5. **Day 3:** Fix moderate AI violations (Category 3) - 2-3 hours
        6. **Day 3:** Fix minor AI violations (Category 4) - 0.5-1 hour
        7. **Day 3-4:** Wait for Meta template approval
        8. **Day 4:** Implement template ID usage (Category 5, Tasks 3-4) - 2-3 hours
        9. **Day 4:** Complete testing and deploy to staging
        10. **Day 5:** Deploy to production with monitoring
      MARKDOWN
    end

    # Generate out-of-scope section documenting flows excluded from Phase 2
    # Implements Requirement 19.1-19.5: Verify No Copy Exists for C2A
    #
    # This section documents flows that are explicitly out of scope for Phase 2 corrections.
    # Currently, C2A is the only flow marked as out of scope because no copy is defined
    # in the PDF specification per AI_Usage_Rules section 6.
    #
    # Requirements:
    #   - Req 19.1: Verify AI_Usage_Rules section 6 states C2A has no copy defined in PDF
    #   - Req 19.2: Confirm audit report marks C2A as "pendiente de definición"
    #   - Req 19.3: Verify no code changes are attempted for C2A in Phase 2
    #   - Req 19.4: Document C2A as out of scope until copy specification is provided
    #   - Req 19.5: Note C2A in audit report "Pendientes / fuera de alcance" section
    #
    # @return [String] Markdown section documenting out-of-scope flows
    def generate_out_of_scope_section
      <<~MARKDOWN
        ## 9. Pendientes / Fuera de Alcance

        This section documents flows that are explicitly out of scope for Phase 2 corrections.
        These flows should NOT be implemented until their requirements are clarified and documented.

        ### C2A: Cliente - Consulta de Ciudad/Zona (Pendiente de Definición)

        **Status:** ⏸️ **Out of Scope** - No copy defined in PDF specification

        **Reason:** Per AI_Usage_Rules section 6 (documented in `prompt-kiro-correccion-copys-ia.md`),
        the C2A flow has no copy defined in the source of truth PDF (`trato-flujos-v4-ux-copy.pdf`).

        **Action Required Before Implementation:**
        - UX team must define the official copy for C2A in the PDF specification
        - Copy must be reviewed and approved by product team
        - Once copy is defined, C2A should be added to a future audit/correction phase

        **Phase 2 Instruction:**
        - ❌ **DO NOT** attempt to implement C2A in Phase 2
        - ❌ **DO NOT** create messages in `elisa_es.yml` for C2A
        - ❌ **DO NOT** add AI implementation for C2A flows
        - ✅ **WAIT** for official copy specification from UX team

        **Related Flows:**
        - **C2D** (cliente pregunta ciudad/zona) - Similar flow that IS implemented and documented
        - C2A can follow similar pattern once copy is defined

        ### Summary

        **Total Flows Out of Scope:** 1 (C2A)
        **Reason:** Missing copy definition in PDF specification
        **Next Steps:** UX team to define and document C2A copy in official PDF specification
      MARKDOWN
    end

    # Save markdown content to file
    # @param markdown [String] Markdown content
    # @return [String] Path to saved file
    def save_to_file(markdown)
      ensure_output_directory_exists
      File.write(OUTPUT_PATH, markdown)
      OUTPUT_PATH.to_s
    rescue IOError => e
      raise ReportGenerationError, "Failed to write report: #{e.message}"
    end

    # Ensure output directory exists
    def ensure_output_directory_exists
      FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))
    end

    # Calculate final statistics
    # @return [Hash] Statistics about the report
    def calculate_final_stats
      {
        total_messages: @yaml_inventory[:stats][:total],
        provider_messages: @yaml_inventory[:stats][:provider],
        client_messages: @yaml_inventory[:stats][:client],
        total_violations: @ai_violations.count,
        critical_violations: @ai_violations.count { |v| v.severity == :critical },
        moderate_violations: @ai_violations.count { |v| v.severity == :moderate },
        minor_violations: @ai_violations.count { |v| v.severity == :minor },
        template_requirements: @template_requirements.count,
        missing_templates: @template_requirements.count { |t| t.yaml_key.include?('MISSING') }
      }
    end

    # Truncate message text for display in tables
    # @param text [String] Message text
    # @param max_length [Integer] Maximum length before truncation
    # @return [String] Truncated text
    def truncate_message(text, max_length = 60)
      return '' if text.nil?

      # Normalize whitespace and escape pipe characters
      normalized = text.gsub("\n", ' ').gsub(/\s+/, ' ').strip
      escaped = normalized.gsub('|', '\\|')

      # Truncate if needed
      return escaped if escaped.length <= max_length

      "#{escaped[0...max_length]}..."
    end

    # Shorten file path for display
    # @param file_path [String] Full file path
    # @return [String] Shortened path
    def shorten_file_path(file_path)
      # Remove Rails.root prefix if present
      path = file_path.to_s.gsub(Rails.root.to_s + '/', '')

      # Further shorten if still too long
      return path if path.length <= 40

      # Show beginning and end
      "...#{path[-37..]}"
    end
  end
end
