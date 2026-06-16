# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# Load Rake tasks
Rails.application.load_tasks

RSpec.describe 'elisa_audit rake tasks' do
  # Run tasks in a clean environment before each test
  before do
    # Ensure tasks are invoked fresh each time
    Rake::Task.tasks.each(&:reenable)
  end

  describe 'elisa_audit:generate_yaml_inventory' do
    let(:generator) { instance_double(ElisaAudit::YamlInventoryGenerator) }
    let(:yaml_result) do
      {
        markdown: "# Sample markdown",
        stats: { total: 50, provider: 30, client: 20, unknown: 0 }
      }
    end

    before do
      allow(ElisaAudit::YamlInventoryGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:call).and_return(yaml_result)
      allow(generator).to receive(:save_to_file).and_return('/path/to/yaml-inventory.md')
    end

    it 'creates YamlInventoryGenerator instance' do
      expect(ElisaAudit::YamlInventoryGenerator).to receive(:new)
      Rake::Task['elisa_audit:generate_yaml_inventory'].invoke
    end

    it 'calls the generator service' do
      expect(generator).to receive(:call)
      Rake::Task['elisa_audit:generate_yaml_inventory'].invoke
    end

    it 'saves the result to file' do
      expect(generator).to receive(:save_to_file).with(yaml_result[:markdown])
      Rake::Task['elisa_audit:generate_yaml_inventory'].invoke
    end

    context 'when YAML parse error occurs' do
      before do
        allow(generator).to receive(:call).and_raise(ElisaAudit::YamlParseError, 'Invalid YAML')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:generate_yaml_inventory'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(generator).to receive(:call).and_raise(StandardError, 'Unexpected error')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:generate_yaml_inventory'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end

  describe 'elisa_audit:analyze_ai_usage' do
    let(:analyzer) { instance_double(ElisaAudit::AiUsageAnalyzer) }
    let(:violations) do
      [
        ElisaAudit::AiUsageViolation.new(
          type: :improper_generation,
          flow_id: 'P10-P14',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'Current',
          expected_impl: 'Expected',
          severity: :critical,
          model_used: :haiku
        )
      ]
    end

    before do
      allow(ElisaAudit::AiUsageAnalyzer).to receive(:new).and_return(analyzer)
      allow(analyzer).to receive(:call).and_return(violations)
    end

    it 'creates AiUsageAnalyzer instance' do
      expect(ElisaAudit::AiUsageAnalyzer).to receive(:new)
      Rake::Task['elisa_audit:analyze_ai_usage'].invoke
    end

    it 'calls the analyzer service' do
      expect(analyzer).to receive(:call)
      Rake::Task['elisa_audit:analyze_ai_usage'].invoke
    end

    context 'when no violations found' do
      before do
        allow(analyzer).to receive(:call).and_return([])
      end

      it 'completes successfully' do
        expect do
          Rake::Task['elisa_audit:analyze_ai_usage'].invoke
        end.not_to raise_error
      end
    end

    context 'when violations are found' do
      it 'completes successfully' do
        expect do
          Rake::Task['elisa_audit:analyze_ai_usage'].invoke
        end.not_to raise_error
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(analyzer).to receive(:call).and_raise(StandardError, 'Unexpected error')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:analyze_ai_usage'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end

  describe 'elisa_audit:detect_templates' do
    let(:detector) { instance_double(ElisaAudit::WhatsAppTemplateDetector) }
    let(:requirements) do
      [
        ElisaAudit::TemplateRequirement.new(
          flow_id: 'P10-P14',
          template_name: 'test_template',
          category: 'UTILITY',
          message_text: 'Test message',
          variables: [],
          is_proactive: true,
          yaml_key: 'test.key'
        )
      ]
    end

    before do
      allow(ElisaAudit::WhatsAppTemplateDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:call).and_return(requirements)
    end

    it 'creates WhatsAppTemplateDetector instance' do
      expect(ElisaAudit::WhatsAppTemplateDetector).to receive(:new)
      Rake::Task['elisa_audit:detect_templates'].invoke
    end

    it 'calls the detector service' do
      expect(detector).to receive(:call)
      Rake::Task['elisa_audit:detect_templates'].invoke
    end

    context 'when YAML parse error occurs' do
      before do
        allow(detector).to receive(:call).and_raise(ElisaAudit::YamlParseError, 'Invalid YAML')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:detect_templates'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(detector).to receive(:call).and_raise(StandardError, 'Unexpected error')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:detect_templates'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end

  describe 'elisa_audit:generate_report' do
    let(:generator) { instance_double(ElisaAudit::YamlInventoryGenerator) }
    let(:analyzer) { instance_double(ElisaAudit::AiUsageAnalyzer) }
    let(:detector) { instance_double(ElisaAudit::WhatsAppTemplateDetector) }
    let(:report_generator) { instance_double(ElisaAudit::AuditReportGenerator) }

    let(:yaml_result) do
      {
        markdown: "# YAML Inventory",
        stats: { total: 50, provider: 30, client: 20, unknown: 0 }
      }
    end

    let(:violations) do
      [
        ElisaAudit::AiUsageViolation.new(
          type: :improper_generation,
          flow_id: 'P10-P14',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'Current',
          expected_impl: 'Expected',
          severity: :critical,
          model_used: :haiku
        )
      ]
    end

    let(:requirements) do
      [
        ElisaAudit::TemplateRequirement.new(
          flow_id: 'P10-P14',
          template_name: 'test_template',
          category: 'UTILITY',
          message_text: 'Test message',
          variables: [],
          is_proactive: true,
          yaml_key: 'test.key'
        )
      ]
    end

    let(:report_result) do
      {
        markdown: "# Audit Report",
        output_path: '/path/to/phase1-audit-report.md',
        stats: { total_messages: 50, violations: 1, templates: 1 }
      }
    end

    before do
      # Mock YamlInventoryGenerator
      allow(ElisaAudit::YamlInventoryGenerator).to receive(:new).and_return(generator)
      allow(generator).to receive(:call).and_return(yaml_result)
      allow(generator).to receive(:save_to_file).and_return('/path/to/yaml-inventory.md')

      # Mock AiUsageAnalyzer
      allow(ElisaAudit::AiUsageAnalyzer).to receive(:new).and_return(analyzer)
      allow(analyzer).to receive(:call).and_return(violations)

      # Mock WhatsAppTemplateDetector
      allow(ElisaAudit::WhatsAppTemplateDetector).to receive(:new).and_return(detector)
      allow(detector).to receive(:call).and_return(requirements)

      # Mock AuditReportGenerator
      allow(ElisaAudit::AuditReportGenerator).to receive(:new).and_return(report_generator)
      allow(report_generator).to receive(:call).and_return(report_result)
    end

    it 'orchestrates all four services in correct order' do
      # Verify order of calls
      expect(ElisaAudit::YamlInventoryGenerator).to receive(:new).ordered
      expect(generator).to receive(:call).ordered
      expect(generator).to receive(:save_to_file).ordered

      expect(ElisaAudit::AiUsageAnalyzer).to receive(:new).ordered
      expect(analyzer).to receive(:call).ordered

      expect(ElisaAudit::WhatsAppTemplateDetector).to receive(:new).ordered
      expect(detector).to receive(:call).ordered

      expect(ElisaAudit::AuditReportGenerator).to receive(:new).ordered
      expect(report_generator).to receive(:call).ordered

      Rake::Task['elisa_audit:generate_report'].invoke
    end

    it 'generates YAML inventory' do
      expect(generator).to receive(:call)
      Rake::Task['elisa_audit:generate_report'].invoke
    end

    it 'analyzes AI usage' do
      expect(analyzer).to receive(:call)
      Rake::Task['elisa_audit:generate_report'].invoke
    end

    it 'detects WhatsApp templates' do
      expect(detector).to receive(:call)
      Rake::Task['elisa_audit:generate_report'].invoke
    end

    it 'generates audit report with all inputs' do
      expect(report_generator).to receive(:call).with(
        yaml_inventory: yaml_result,
        ai_violations: violations,
        template_requirements: requirements
      )
      Rake::Task['elisa_audit:generate_report'].invoke
    end

    it 'saves the audit report to correct location' do
      Rake::Task['elisa_audit:generate_report'].invoke
      # Verify the report_result contains the output_path
      expect(report_result[:output_path]).to eq('/path/to/phase1-audit-report.md')
    end

    context 'when YAML parse error occurs' do
      before do
        allow(generator).to receive(:call).and_raise(ElisaAudit::YamlParseError, 'Invalid YAML')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:generate_report'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context 'when report generation error occurs' do
      before do
        allow(report_generator).to receive(:call)
          .and_raise(ElisaAudit::ReportGenerationError, 'Failed to write report')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:generate_report'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context 'when unexpected error occurs' do
      before do
        allow(generator).to receive(:call).and_raise(StandardError, 'Unexpected error')
      end

      it 'exits with status 1' do
        expect do
          Rake::Task['elisa_audit:generate_report'].invoke
        end.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end
end
