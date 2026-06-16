# frozen_string_literal: true

require_relative 'data_models'

module ElisaAudit
  # Analyzes service files to detect ClaudeService.call invocations and verify
  # against AI usage rules defined in AiUsageRules module.
  #
  # This service:
  # - Scans all relevant service files for ClaudeService.call usage
  # - Extracts model parameter (:haiku or :sonnet) from each invocation
  # - Infers flow ID from surrounding code context (method names, comments, conditionals)
  # - Cross-references detected usage against AiUsageRules::FLOWS
  #
  # Usage:
  #   analyzer = ElisaAudit::AiUsageAnalyzer.new
  #   violations = analyzer.call
  #   violations.each { |v| puts "#{v.flow_id}: #{v.current_impl}" }
  class AiUsageAnalyzer
    # All service files that may contain ClaudeService.call invocations
    # organized by category for better maintainability
    SERVICE_FILES = [
      # Core conversation handlers
      'app/services/onboarding_service.rb',
      'app/services/provider_conversation_handler.rb',
      'app/services/client_assistant_orchestrator.rb',
      'app/services/provider_assistant.rb',
      'app/services/client_assistant.rb',

      # Assistant services
      'app/services/assistants/appointment_service.rb',
      'app/services/assistants/availability_service.rb',
      'app/services/assistants/client_prompt_builder.rb',
      'app/services/assistants/conversation_persistence_service.rb',
      'app/services/assistants/escalation_detector.rb',
      'app/services/assistants/financial_query_service.rb',
      'app/services/assistants/provider_prompt_builder.rb',
      'app/services/assistants/provider_search_service.rb',
      'app/services/assistants/review_collection_service.rb',
      'app/services/assistants/review_summary_service.rb',
      'app/services/assistants/social_media_service.rb',
      'app/services/assistants/task_service.rb',
      'app/services/assistants/work_day_service.rb',

      # Other related services
      'app/services/job_registration_service.rb',
      'app/services/directory_service.rb',
      'app/services/social_service.rb'
    ].freeze

    # Data structure for detected AI usage
    AiUsage = Struct.new(
      :flow_id,        # String: inferred P6A, C1A, etc.
      :file_path,      # String: path to service file
      :line_number,    # Integer: line number in file
      :method_name,    # String: method where usage occurs
      :model_used,     # Symbol: :haiku, :sonnet, or nil
      :context_lines,  # Array<String>: surrounding code lines for inference
      keyword_init: true
    )

    # Analyzes all service files and returns violations (not just usages)
    # Performs two types of detection:
    # 1. Improper AI usage (AI used where it shouldn't be)
    # 2. Missing AI usage (flow requires AI but none detected)
    #
    # @param include_missing_ai [Boolean] Whether to check for missing AI usage (default: true)
    # @return [Array<AiUsageViolation>] List of AI usage violations found
    def call(include_missing_ai: true)
      violations = []
      all_usages = []
      detected_flow_ids = Set.new

      # Phase 1: Scan all service files for AI usage
      SERVICE_FILES.each do |file_path|
        full_path = Rails.root.join(file_path)

        # Gracefully handle missing files - log and continue
        unless File.exist?(full_path)
          Rails.logger.warn("[AiUsageAnalyzer] File not found, skipping: #{file_path}")
          next
        end

        usages = analyze_file(full_path.to_s)
        all_usages += usages

        # Track which flows have AI usage detected
        usages.each { |usage| detected_flow_ids.add(usage.flow_id) }

        # Detect violations in detected usages
        violations += detect_violations(usages)
      rescue StandardError => e
        # Log error but continue with other files - graceful degradation
        Rails.logger.error("[AiUsageAnalyzer] Failed to analyze #{file_path}: #{e.message}")
        Rails.logger.error("[AiUsageAnalyzer] Backtrace: #{e.backtrace.first(3).join("\n")}")
      end

      # Phase 2: Check for missing AI usage (if requested)
      if include_missing_ai
        missing_violations = detect_missing_ai_usage(detected_flow_ids.to_a)
        violations += missing_violations
      end

      violations
    rescue StandardError => e
      Rails.logger.error("[AiUsageAnalyzer] Critical error in call method: #{e.message}")
      Rails.logger.error("[AiUsageAnalyzer] Backtrace: #{e.backtrace.first(5).join("\n")}")
      violations # Return partial results
    end

    # Analyzes a single service file for ClaudeService.call invocations
    # @param file_path [String] Absolute path to the service file
    # @return [Array<AiUsage>] List of detected usages in this file
    def analyze_file(file_path)
      return [] unless File.exist?(file_path)

      content = File.read(file_path)
      lines = content.split("\n")
      usages = []

      lines.each_with_index do |line, index|
        next unless line.match?(/ClaudeService\.call/)

        usage = extract_usage(file_path, lines, index)
        usages << usage if usage
      end

      usages
    rescue StandardError => e
      Rails.logger.error("[AiUsageAnalyzer] Error reading #{file_path}: #{e.message}")
      []
    end

    private

    # Extracts AI usage details from a ClaudeService.call invocation
    # @param file_path [String] Path to the file
    # @param lines [Array<String>] All lines in the file
    # @param call_index [Integer] Index of the line containing ClaudeService.call
    # @return [AiUsage, nil] Extracted usage or nil if couldn't parse
    def extract_usage(file_path, lines, call_index)
      # Extract model parameter from the call
      model = extract_model_parameter(lines, call_index)

      # Extract method name containing the call
      method_name = extract_method_name(lines, call_index)

      # Get surrounding context for flow ID inference
      context_lines = extract_context_lines(lines, call_index)

      # Infer flow ID from context
      flow_id = infer_flow_id(context_lines, method_name, file_path)

      AiUsage.new(
        flow_id: flow_id,
        file_path: file_path,
        line_number: call_index + 1, # Convert to 1-indexed
        method_name: method_name,
        model_used: model,
        context_lines: context_lines
      )
    end

    # Extracts the model parameter from ClaudeService.call
    # Looks forward from call_index to find "model: :haiku" or "model: :sonnet"
    # @param lines [Array<String>] All lines in the file
    # @param call_index [Integer] Index of ClaudeService.call line
    # @return [Symbol, nil] :haiku, :sonnet, or nil if not found
    def extract_model_parameter(lines, call_index)
      # Search in current line and next 10 lines for model parameter
      search_range = (call_index..[call_index + 10, lines.length - 1].min)

      search_range.each do |i|
        line = lines[i]

        # Match "model: :haiku" or "model: :sonnet"
        if line.match?(/model:\s*:haiku/)
          return :haiku
        elsif line.match?(/model:\s*:sonnet/)
          return :sonnet
        end

        # Stop searching if we hit the end of the method call
        break if line.match?(/^\s*\)/) && i > call_index
      end

      nil
    end

    # Extracts the method name containing the ClaudeService.call
    # Searches backward from call_index to find "def method_name"
    # @param lines [Array<String>] All lines in the file
    # @param call_index [Integer] Index of ClaudeService.call line
    # @return [String] Method name or "unknown"
    def extract_method_name(lines, call_index)
      # Search backward up to 50 lines for method definition
      search_start = [call_index - 50, 0].max

      (call_index).downto(search_start) do |i|
        line = lines[i]

        # Match "def method_name" or "def self.method_name"
        match = line.match(/^\s*def\s+(self\.)?(\w+)/)
        return match[2] if match
      end

      'unknown'
    end

    # Extracts surrounding lines for context analysis
    # @param lines [Array<String>] All lines in the file
    # @param call_index [Integer] Index of ClaudeService.call line
    # @return [Array<String>] Context lines (5 before, 5 after)
    def extract_context_lines(lines, call_index)
      start_idx = [call_index - 5, 0].max
      end_idx = [call_index + 5, lines.length - 1].min

      lines[start_idx..end_idx]
    end

    # Infers flow ID from context: method name, comments, conditionals, file path
    # Uses pattern matching and keyword detection
    # @param context_lines [Array<String>] Surrounding code lines
    # @param method_name [String] Name of the method containing the call
    # @param file_path [String] Path to the file
    # @return [String] Inferred flow ID (e.g., "P6A", "C1A") or "unknown"
    def infer_flow_id(context_lines, method_name, file_path)
      # Strategy 1: Look for explicit flow ID mentions in comments
      context_lines.each do |line|
        # Match patterns like "# P6A", "# Flow P6A", "P6A:", etc.
        match = line.match(/[#\s](P\d+[A-E]?|C\d+[A-G]?)[\s:]/)
        return match[1] if match
      end

      # Strategy 2: Infer from method name patterns
      flow_from_method = infer_from_method_name(method_name)
      return flow_from_method if flow_from_method

      # Strategy 3: Infer from file path
      flow_from_file = infer_from_file_path(file_path)
      return flow_from_file if flow_from_file

      # Strategy 4: Look for flow-related keywords in context
      infer_from_keywords(context_lines)
    end

    # Infers flow ID from method name patterns
    # @param method_name [String] Method name
    # @return [String, nil] Flow ID or nil
    def infer_from_method_name(method_name)
      case method_name
      when /bio/, /generate_bio/, /regenerate_bio/
        'P6A' # Bio generation
      when /morning_summary/, /resumen_matutino/
        'P16' # Morning summary
      when /financial_query/, /consulta_financiera/
        'P17' # Financial query
      when /emergency/, /escalate/, /urgente/
        'C5A' # Emergency detection
      when /review/, /reseña/
        'C7A' # Review collection
      when /appointment/, /cita/
        'C4A' # Appointment management
      when /city/, /ciudad/, /zone/, /zona/
        'P3E' # City/zone extraction
      when /facebook/, /social/
        'P20' # Facebook connection
      when /photo/, /foto/
        'P7A' # Photo tagging
      when /gasto/, /expense/
        'P15' # Expense detection
      else
        nil
      end
    end

    # Infers flow ID from file path patterns
    # @param file_path [String] File path
    # @return [String, nil] Flow ID or nil
    def infer_from_file_path(file_path)
      case file_path
      when /onboarding_service/
        'P1A' # Onboarding flows
      when /provider_conversation_handler/
        'P10-P14' # Provider general conversations
      when /client_assistant_orchestrator/
        'C1A' # Client conversations
      when /escalation_detector/
        'C5A' # Emergency escalation
      when /financial_query_service/
        'P17' # Financial queries
      when /review_collection_service/
        'C7A' # Review collection
      when /appointment_service/
        'C4A' # Appointment management
      when /social_media_service/
        'P20' # Social media connections
      else
        nil
      end
    end

    # Infers flow ID from keywords in surrounding code
    # @param context_lines [Array<String>] Context lines
    # @return [String] Flow ID or "unknown"
    def infer_from_keywords(context_lines)
      context_text = context_lines.join("\n").downcase

      return 'P6A' if context_text.include?('bio') || context_text.include?('perfil')
      return 'P16' if context_text.include?('resumen matutino') || context_text.include?('morning')
      return 'P17' if context_text.include?('financiera') || context_text.include?('financial')
      return 'C5A' if context_text.include?('emergency') || context_text.include?('urgente')
      return 'C7A' if context_text.include?('review') || context_text.include?('reseña')
      return 'C4A' if context_text.include?('cita') || context_text.include?('appointment')
      return 'P3E' if context_text.include?('ciudad') || context_text.include?('zone')
      return 'P20' if context_text.include?('facebook') || context_text.include?('social')
      return 'P15' if context_text.include?('gasto') || context_text.include?('expense')

      'unknown'
    end

    # Detects violations by comparing detected AI usages against AiUsageRules
    # Handles three main categories:
    # 1. Improper AI usage (AI used where it shouldn't be)
    # 2. Wrong model (correct usage but wrong Haiku/Sonnet assignment)
    # 3. Missing AI (flow needs AI but none detected - requires separate analysis)
    #
    # @param usages [Array<AiUsage>] Detected AI usages from service files
    # @return [Array<AiUsageViolation>] List of violations found
    def detect_violations(usages)
      violations = []

      usages.each do |usage|
        violation = check_usage_against_rules(usage)
        violations << violation if violation
      end

      violations
    rescue StandardError => e
      # Graceful degradation: log error but return partial results
      Rails.logger.error("[AiUsageAnalyzer] Error detecting violations: #{e.message}")
      Rails.logger.error("[AiUsageAnalyzer] Backtrace: #{e.backtrace.first(3).join("\n")}")
      violations
    end

    # Checks a single AI usage against the expected rules for its flow
    # Returns the first violation found, prioritizing by severity
    #
    # @param usage [AiUsage] Detected AI usage
    # @return [AiUsageViolation, nil] Violation if found, nil otherwise
    def check_usage_against_rules(usage)
      # Skip unknown flows - can't validate without flow ID
      return nil if usage.flow_id == 'unknown'

      expected = AiUsageRules.expected_for_flow(usage.flow_id)

      # Skip undocumented flows - these need manual review
      return nil if expected[:type] == :unknown

      # Check for different violation types in priority order
      # 1. Critical: improper generation (AI where it shouldn't be)
      # 2. Moderate: wrong usage type (interpretation vs extraction vs generation mismatch)
      # 3. Minor: wrong model assignment
      detect_improper_generation(usage, expected) ||
        detect_usage_type_mismatch(usage, expected) ||
        detect_wrong_model(usage, expected)
    end

    # Detects improper generation: AI is generating message content but shouldn't be
    # This covers:
    # - Critical: fixed_template flows using ANY AI (e.g., P10-P14, P1A-P5)
    # - Moderate: flows that should use AI for extraction/interpretation but are generating text
    #
    # @param usage [AiUsage] Detected AI usage
    # @param expected [Hash] Expected configuration from AiUsageRules
    # @return [AiUsageViolation, nil]
    def detect_improper_generation(usage, expected)
      # Case 1: Fixed template flows must NEVER use AI for anything
      if expected[:type] == :fixed_template
        return create_violation(
          type: :improper_generation,
          usage: usage,
          expected: expected,
          current_description: "ClaudeService.call detected in method '#{usage.method_name}' with model #{usage.model_used}",
          expected_description: "Must be 100% fixed template from elisa_es.yml with NO AI usage. #{expected[:note]}",
          severity: calculate_severity_for_fixed_template(expected)
        )
      end

      # Case 2: Flows that should only extract/interpret but appear to be generating
      # Note: This is heuristic-based - if method name suggests generation but flow type is extraction/interpretation
      if %i[extraction interpretation interpretation_photos detection_semantic].include?(expected[:type])
        if method_suggests_generation?(usage.method_name)
          return create_violation(
            type: :improper_generation,
            usage: usage,
            expected: expected,
            current_description: "Method '#{usage.method_name}' suggests text generation, but flow type is #{expected[:type]}",
            expected_description: "Should only use AI for #{expected[:type]}. Output messages must be fixed templates. #{expected[:note]}",
            severity: :moderate
          )
        end
      end

      nil
    end

    # Detects usage type mismatch: AI is used but for wrong purpose
    # Examples:
    # - Extraction flow (P3E) using generation instead of extraction
    # - Interpretation flow (C4A) generating text instead of just routing
    #
    # @param usage [AiUsage] Detected AI usage
    # @param expected [Hash] Expected configuration from AiUsageRules
    # @return [AiUsageViolation, nil]
    def detect_usage_type_mismatch(usage, expected)
      # For now, this is a placeholder for more sophisticated detection
      # Would require deeper prompt analysis to determine if AI is being used correctly
      # Future enhancement: analyze prompt content to classify usage intent
      nil
    end

    # Detects wrong model usage: AI is being used correctly but with wrong model (haiku vs sonnet)
    # This is a minor violation since functionality is correct, just performance/cost implications
    #
    # @param usage [AiUsage] Detected AI usage
    # @param expected [Hash] Expected configuration from AiUsageRules
    # @return [AiUsageViolation, nil]
    def detect_wrong_model(usage, expected)
      # Only check if expected model is specified and doesn't match
      return nil unless expected[:model]
      return nil if expected[:model] == usage.model_used
      return nil unless usage.model_used # Skip if we couldn't detect the model

      create_violation(
        type: :wrong_model,
        usage: usage,
        expected: expected,
        current_description: "Using #{usage.model_used} model in method '#{usage.method_name}'",
        expected_description: "Should use #{expected[:model]} model per AI_Usage_Rules. #{expected[:note]}",
        severity: :minor
      )
    end

    # Creates a violation record with consistent structure
    # Centralizes violation creation to ensure all required fields are populated
    #
    # @param type [Symbol] Violation type
    # @param usage [AiUsage] Detected usage
    # @param expected [Hash] Expected configuration
    # @param current_description [String] Description of current implementation
    # @param expected_description [String] Description of expected implementation
    # @param severity [Symbol] Severity level
    # @return [AiUsageViolation]
    def create_violation(type:, usage:, expected:, current_description:, expected_description:, severity:)
      ElisaAudit::AiUsageViolation.new(
        type: type,
        flow_id: usage.flow_id,
        file_path: usage.file_path,
        line_number: usage.line_number,
        method_name: usage.method_name,
        current_impl: current_description,
        expected_impl: expected_description,
        severity: severity,
        model_used: usage.model_used
      )
    end

    # Calculates severity for fixed_template violations based on status
    # Critical status (like P10-P14) gets :critical severity
    # Others get :moderate severity
    #
    # @param expected [Hash] Expected configuration
    # @return [Symbol] :critical or :moderate
    def calculate_severity_for_fixed_template(expected)
      expected[:status] == :critical_verify ? :critical : :moderate
    end

    # Heuristic check: does method name suggest text generation?
    # Looks for keywords like: generate, create, build, compose, write, produce
    #
    # @param method_name [String] Method name to check
    # @return [Boolean] true if method suggests generation
    def method_suggests_generation?(method_name)
      generation_keywords = %w[generate create build compose write produce make construct]
      method_lower = method_name.to_s.downcase

      generation_keywords.any? { |keyword| method_lower.include?(keyword) }
    end

    # Detects missing AI usage: flows that should have AI but don't
    # This requires a separate analysis pass since we're looking for ABSENCE of AI
    # Called separately from main violation detection flow
    #
    # Strategy:
    # 1. Get all flows that require AI (extraction, interpretation, generation types)
    # 2. Check if we detected any AI usage for those flows
    # 3. Flag flows with required AI but no detected usage
    #
    # @param detected_flow_ids [Array<String>] Flow IDs where we detected AI usage
    # @return [Array<AiUsageViolation>] Missing AI violations
    def detect_missing_ai_usage(detected_flow_ids)
      violations = []

      # Get all flows that require AI
      required_ai_flows = AiUsageRules::FLOWS.select do |_flow_id, config|
        %i[extraction generation generation_closing generation_summary interpretation
           interpretation_photos tagging detection_semantic].include?(config[:type])
      end

      required_ai_flows.each do |flow_id, config|
        # Skip if we detected AI usage for this flow
        next if detected_flow_ids.include?(flow_id)

        # Skip flows marked as "implement" - they're known to be missing
        next if config[:status] == :implement

        # Skip flows marked as "correct" - assume they're implemented correctly
        next if config[:status] == :correct

        # Create violation for missing AI
        violations << create_missing_ai_violation(flow_id, config)
      end

      violations
    rescue StandardError => e
      Rails.logger.error("[AiUsageAnalyzer] Error detecting missing AI: #{e.message}")
      []
    end

    # Creates a violation record for missing AI usage
    # @param flow_id [String] Flow identifier
    # @param expected [Hash] Expected configuration
    # @return [AiUsageViolation]
    def create_missing_ai_violation(flow_id, expected)
      violation_type = case expected[:type]
                       when :extraction
                         :missing_extraction
                       when :interpretation, :interpretation_photos
                         :missing_interpretation
                       else
                         :missing_extraction # Default for other AI types
                       end

      severity = case expected[:status]
                 when :critical_verify
                   :critical
                 when :verify
                   :moderate
                 else
                   :minor
                 end

      ElisaAudit::AiUsageViolation.new(
        type: violation_type,
        flow_id: flow_id,
        file_path: 'unknown',
        line_number: 0,
        method_name: 'unknown',
        current_impl: "No ClaudeService.call detected for flow #{flow_id}",
        expected_impl: "Should use AI for #{expected[:type]}. #{expected[:note]}",
        severity: severity,
        model_used: nil
      )
    end
  end
end
