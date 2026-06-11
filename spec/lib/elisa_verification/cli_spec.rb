# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../lib/elisa_verification/verify_messages'

RSpec.describe ElisaVerification::CLI do
  describe '#run (Task 11.3: Dry-run mode)' do
    let(:yaml_path) { 'config/locales/elisa_es.yml' }
    let(:spec_path) { '../KIRO_PROMPT_FLOWS_v5.md' }
    let(:report_path) { 'tmp/test-verification-report.md' }
    let(:args) { ['--yaml', yaml_path, '--spec', spec_path, '--report', report_path] }
    let(:cli) { described_class.new(args) }

    before do
      # Ensure test report directory exists
      FileUtils.mkdir_p('tmp')
      # Clean up any existing test report
      FileUtils.rm_f(report_path)
    end

    after do
      # Clean up test report
      FileUtils.rm_f(report_path)
    end

    context 'when running in dry-run mode (default)' do
      it 'performs verification without modifying YAML file' do
        # Capture stdout to verify output messages
        output = capture_stdout do
          result = cli.run
          expect(result).to eq(0)
        end

        # Verify configuration display
        expect(output).to include('=== Elisa Message Copy Verification ===')
        expect(output).to include("YAML file: #{yaml_path}")
        expect(output).to include("Spec file: #{spec_path}")
        expect(output).to include("Report: #{report_path}")
        expect(output).to include('Apply corrections: NO (dry-run)')

        # Verify component execution messages
        expect(output).to include('📖 Loading V5 specification...')
        expect(output).to include('✓ Parsed')
        expect(output).to include('📝 Loading YAML file...')
        expect(output).to include('✓ Loaded')
        expect(output).to include('🔍 Comparing messages...')
        expect(output).to include('✓ Analyzed')
        expect(output).to include('📊 Generating report...')
        expect(output).to include('✓ Report saved to')

        # Verify dry-run summary section
        expect(output).to include('VERIFICATION SUMMARY')
        expect(output).to include('📋 Findings:')
        expect(output).to include('Total messages checked:')
        expect(output).to include('Messages matching v5:')
        expect(output).to include('Messages needing correction:')
        expect(output).to include('📄 Detailed report available at:')

        # Verify dry-run mode prompt
        expect(output).to include('⚠️  DRY-RUN MODE')
        expect(output).to include('No files have been modified.')
        expect(output).to include('Review the report above, then run with --apply to make changes:')
        expect(output).to include('bundle exec ruby')
        expect(output).to include('--apply')
      end

      it 'generates and saves the verification report' do
        cli.run

        # Verify report file was created
        expect(File.exist?(report_path)).to be true

        # Verify report contains expected sections
        report_content = File.read(report_path)
        expect(report_content).to include('# Elisa Message Copy Verification Report')
        expect(report_content).to include('## Summary')
        expect(report_content).to include('Total messages checked:')
        expect(report_content).to include('Messages matching v5:')
      end

      it 'does not modify the YAML file' do
        # Get original YAML content and modification time
        original_content = File.read(yaml_path)
        original_mtime = File.mtime(yaml_path)

        # Run verification
        cli.run

        # Verify YAML file was not modified
        expect(File.read(yaml_path)).to eq(original_content)
        expect(File.mtime(yaml_path)).to eq(original_mtime)
      end

      it 'displays appropriate message when all messages match v5' do
        # This test would require a setup where all messages match
        # For now, we'll skip this as it requires complex fixture setup
        skip 'Requires fixture with all matching messages'
      end
    end

    context 'when files are missing' do
      it 'reports error when YAML file does not exist' do
        bad_args = ['--yaml', 'nonexistent.yml', '--spec', spec_path, '--report', report_path]
        bad_cli = described_class.new(bad_args)

        output = capture_stderr do
          result = bad_cli.run
          expect(result).to eq(1)
        end

        expect(output).to include('YAML file not found')
      end

      it 'reports error when spec file does not exist' do
        bad_args = ['--yaml', yaml_path, '--spec', 'nonexistent.md', '--report', report_path]
        bad_cli = described_class.new(bad_args)

        output = capture_stderr do
          result = bad_cli.run
          expect(result).to eq(1)
        end

        expect(output).to include('Spec file not found')
      end

      it 'reports error when report directory does not exist' do
        bad_args = ['--yaml', yaml_path, '--spec', spec_path, '--report', 'nonexistent_dir/report.md']
        bad_cli = described_class.new(bad_args)

        output = capture_stderr do
          result = bad_cli.run
          expect(result).to eq(1)
        end

        expect(output).to include('Report directory not found')
      end
    end

    context 'with --verbose flag' do
      let(:verbose_args) { args + ['--verbose'] }
      let(:verbose_cli) { described_class.new(verbose_args) }

      it 'displays debug information' do
        output = capture_stdout do
          verbose_cli.run
        end

        expect(output).to include('Debug: Configuration loaded')
      end
    end

    context 'with --help flag' do
      let(:help_cli) { described_class.new(['--help']) }

      it 'displays help message and exits' do
        output = capture_stdout do
          result = help_cli.run
          expect(result).to eq(0)
        end

        expect(output).to include('Usage: verify_messages.rb [options]')
        expect(output).to include('Verify Elisa message copies against v5 specification')
        expect(output).to include('--help')
        expect(output).to include('--apply')
        expect(output).to include('--yaml')
        expect(output).to include('--spec')
        expect(output).to include('--report')
        expect(output).to include('--verbose')
      end
    end
  end

  # Helper methods for capturing output
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def capture_stderr
    original_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = original_stderr
  end
end
