# frozen_string_literal: true

namespace :elisa_audit do
  desc 'Generate YAML inventory of all Elisa messages'
  task generate_yaml_inventory: :environment do
    puts '🔍 Generating YAML inventory...'
    puts "Source: #{ElisaAudit::YamlInventoryGenerator::YAML_PATH}"
    puts "Output: #{ElisaAudit::YamlInventoryGenerator::OUTPUT_PATH}"
    puts

    generator = ElisaAudit::YamlInventoryGenerator.new
    result = generator.call

    # Save to file
    output_path = generator.save_to_file(result[:markdown])

    puts '✅ YAML inventory generated successfully!'
    puts
    puts "Statistics:"
    puts "  Total messages: #{result[:stats][:total]}"
    puts "  Provider messages: #{result[:stats][:provider]}"
    puts "  Client messages: #{result[:stats][:client]}"
    puts "  Unknown/unmapped: #{result[:stats][:unknown]}"
    puts
    puts "Output saved to: #{output_path}"
  rescue ElisaAudit::YamlParseError => e
    puts "❌ Error: #{e.message}"
    exit 1
  rescue StandardError => e
    puts "❌ Unexpected error: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end

  desc 'Analyze AI usage in service files'
  task analyze_ai_usage: :environment do
    puts '🤖 Analyzing AI usage in service files...'
    puts

    analyzer = ElisaAudit::AiUsageAnalyzer.new
    violations = analyzer.call

    puts "✅ AI usage analysis complete!"
    puts
    puts "Violations detected: #{violations.count}"

    if violations.any?
      # Group by severity
      critical = violations.count { |v| v.severity == :critical }
      moderate = violations.count { |v| v.severity == :moderate }
      minor = violations.count { |v| v.severity == :minor }

      puts "  🔴 Critical: #{critical}"
      puts "  🟡 Moderate: #{moderate}"
      puts "  🟢 Minor: #{minor}"
      puts
      puts "Details will be included in the audit report."
    else
      puts "  ✅ No violations found - AI usage matches specification!"
    end
  rescue StandardError => e
    puts "❌ Unexpected error: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end

  desc 'Detect required WhatsApp Message Templates'
  task detect_templates: :environment do
    puts '📱 Detecting WhatsApp Message Template requirements...'
    puts

    detector = ElisaAudit::WhatsAppTemplateDetector.new
    requirements = detector.call

    puts '✅ Template detection complete!'
    puts
    puts "Templates required: #{requirements.count}"
    puts "Proactive flows: #{ElisaAudit::WhatsAppTemplateDetector::PROACTIVE_FLOWS.join(', ')}"
    puts
    puts "Templates by flow:"
    requirements.group_by(&:flow_id).each do |flow_id, reqs|
      puts "  #{flow_id}: #{reqs.count} template(s)"
    end
  rescue ElisaAudit::YamlParseError => e
    puts "❌ Error: #{e.message}"
    exit 1
  rescue StandardError => e
    puts "❌ Unexpected error: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
  end

  desc 'Generate complete Phase 1 audit report (orchestrates all services)'
  task generate_report: :environment do
    puts '📋 Generating Phase 1 Audit Report...'
    puts '=' * 60
    puts

    # Step 1: Generate YAML inventory
    puts '[1/4] Generating YAML inventory...'
    generator = ElisaAudit::YamlInventoryGenerator.new
    yaml_inventory = generator.call
    output_path = generator.save_to_file(yaml_inventory[:markdown])
    puts "      ✅ YAML inventory generated (#{yaml_inventory[:stats][:total]} messages)"
    puts "      📄 Saved to: #{output_path}"
    puts

    # Step 2: Analyze AI usage
    puts '[2/4] Analyzing AI usage...'
    analyzer = ElisaAudit::AiUsageAnalyzer.new
    ai_violations = analyzer.call
    puts "      ✅ AI analysis complete (#{ai_violations.count} violations detected)"
    puts

    # Step 3: Detect templates
    puts '[3/4] Detecting WhatsApp Message Templates...'
    detector = ElisaAudit::WhatsAppTemplateDetector.new
    template_requirements = detector.call
    puts "      ✅ Template detection complete (#{template_requirements.count} templates required)"
    puts

    # Step 4: Generate final report
    puts '[4/4] Generating audit report...'
    report_generator = ElisaAudit::AuditReportGenerator.new
    result = report_generator.call(
      yaml_inventory: yaml_inventory,
      ai_violations: ai_violations,
      template_requirements: template_requirements
    )
    puts "      ✅ Audit report generated"
    puts "      📄 Saved to: #{result[:output_path]}"
    puts

    # Display final summary
    puts '=' * 60
    puts '🎉 Phase 1 Audit Report Generation Complete!'
    puts '=' * 60
    puts
    puts 'Summary:'
    puts "  Messages inventoried: #{result[:stats][:total_messages]}"
    puts "  AI violations found: #{result[:stats][:violations]}"
    puts "  Templates required: #{result[:stats][:templates]}"
    puts
    puts 'Next Steps:'
    puts '  1. Review the audit report: .kiro/specs/elisa-message-copy-verification/phase1-audit-report.md'
    puts '  2. Complete manual PDF comparison in Section 2 of the report'
    puts '  3. Review AI violations and template requirements'
    puts '  4. Proceed with Phase 2 corrections after review'
    puts
  rescue ElisaAudit::YamlParseError => e
    puts "❌ YAML Parse Error: #{e.message}"
    exit 1
  rescue ElisaAudit::ReportGenerationError => e
    puts "❌ Report Generation Error: #{e.message}"
    exit 1
  rescue StandardError => e
    puts "❌ Unexpected error: #{e.message}"
    puts
    puts 'Backtrace:'
    puts e.backtrace.first(10)
    exit 1
  end
end
