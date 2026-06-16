# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ElisaAudit::AiUsageAnalyzer do
  let(:analyzer) { described_class.new }

  describe '#call' do
    context 'when service file does not exist' do
      before do
        # Stub SERVICE_FILES to point to non-existent file
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', ['app/services/non_existent.rb'])
      end

      it 'handles gracefully and returns empty array' do
        violations = analyzer.call(include_missing_ai: false)
        expect(violations).to eq([])
      end
    end
  end

  describe '#analyze_file' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when file does not exist' do
      before do
        allow(File).to receive(:exist?).with(file_path).and_return(false)
      end

      it 'returns empty array' do
        result = analyzer.analyze_file(file_path)
        expect(result).to eq([])
      end
    end

    context 'when file contains ClaudeService.call' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def generate_bio
              # P6A: Generate bio
              ClaudeService.call(
                model: :sonnet,
                prompt: "Generate bio"
              )
            end
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'detects ClaudeService.call usage' do
        usages = analyzer.analyze_file(file_path)
        expect(usages).not_to be_empty
        expect(usages.first.flow_id).to eq('P6A')
        expect(usages.first.model_used).to eq(:sonnet)
        expect(usages.first.method_name).to eq('generate_bio')
      end
    end

    context 'when file has no ClaudeService calls' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def simple_method
              "no AI here"
            end
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'returns empty array' do
        usages = analyzer.analyze_file(file_path)
        expect(usages).to be_empty
      end
    end
  end

  describe 'violation detection' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when AI is used in fixed_template flow' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def send_welcome
              # P1A: Welcome message
              ClaudeService.call(
                model: :haiku,
                prompt: "Generate welcome"
              )
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'detects improper_generation violation' do
        violations = analyzer.call
        expect(violations).not_to be_empty

        violation = violations.first
        expect(violation).to be_a(ElisaAudit::AiUsageViolation)
        expect(violation.type).to eq(:improper_generation)
        expect(violation.flow_id).to eq('P1A')
        expect(violation.severity).to eq(:moderate)
      end
    end

    context 'when wrong model is used' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def generate_bio
              # P6A: Generate provider bio
              ClaudeService.call(
                model: :haiku,
                prompt: "Generate bio"
              )
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'detects wrong_model violation' do
        violations = analyzer.call
        expect(violations).not_to be_empty

        violation = violations.first
        expect(violation).to be_a(ElisaAudit::AiUsageViolation)
        expect(violation.type).to eq(:wrong_model)
        expect(violation.flow_id).to eq('P6A')
        expect(violation.severity).to eq(:minor)
        expect(violation.current_impl).to include('haiku')
        expect(violation.expected_impl).to include('sonnet')
      end
    end

    context 'when AI is used correctly' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def generate_bio
              # P6A: Generate provider bio
              ClaudeService.call(
                model: :sonnet,
                prompt: "Generate bio"
              )
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'does not create violations' do
        violations = analyzer.call(include_missing_ai: false)
        expect(violations).to be_empty
      end
    end

    context 'when flow_id is unknown' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def mystery_method
              ClaudeService.call(
                model: :haiku,
                prompt: "Mystery prompt"
              )
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'does not create violations for unknown flows' do
        violations = analyzer.call(include_missing_ai: false)
        expect(violations).to be_empty
      end
    end
  end

  describe 'model parameter extraction' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when model is on same line as call' do
      let(:file_content) do
        <<~RUBY
          ClaudeService.call(model: :haiku, prompt: "test")
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'extracts haiku model' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.model_used).to eq(:haiku)
      end
    end

    context 'when model is on different line' do
      let(:file_content) do
        <<~RUBY
          ClaudeService.call(
            model: :sonnet,
            prompt: "test"
          )
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'extracts sonnet model' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.model_used).to eq(:sonnet)
      end
    end
  end

  describe 'method name extraction' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when call is inside instance method' do
      let(:file_content) do
        <<~RUBY
          def my_method
            ClaudeService.call(model: :haiku, prompt: "test")
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'extracts method name' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.method_name).to eq('my_method')
      end
    end

    context 'when call is inside class method' do
      let(:file_content) do
        <<~RUBY
          def self.class_method
            ClaudeService.call(model: :haiku, prompt: "test")
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'extracts method name without self' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.method_name).to eq('class_method')
      end
    end
  end

  describe 'flow ID inference' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when flow ID is in comment' do
      let(:file_content) do
        <<~RUBY
          # P15: Expense detection
          def detect_expense
            ClaudeService.call(model: :haiku, prompt: "test")
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'infers flow ID from comment' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.flow_id).to eq('P15')
      end
    end

    context 'when flow ID is inferred from method name' do
      let(:file_content) do
        <<~RUBY
          def generate_bio
            ClaudeService.call(model: :sonnet, prompt: "test")
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'infers P6A from method name' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.flow_id).to eq('P6A')
      end
    end

    context 'when flow ID is inferred from file path' do
      let(:file_path) { 'app/services/onboarding_service.rb' }
      let(:file_content) do
        <<~RUBY
          def some_method
            ClaudeService.call(model: :haiku, prompt: "test")
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'infers P1A from file path' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.flow_id).to eq('P1A')
      end
    end

    context 'when flow ID is inferred from keywords in context' do
      let(:file_content) do
        <<~RUBY
          def handle_appointment
            # Handle cita logic
            ClaudeService.call(model: :haiku, prompt: "test")
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'infers C4A from keywords' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.flow_id).to eq('C4A')
      end
    end
  end

  describe 'line number tracking' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when ClaudeService.call is on specific line' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def method_one
              puts "line 3"
            end

            def method_two
              ClaudeService.call(model: :haiku, prompt: "test")
            end
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'tracks correct line number' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.line_number).to eq(7) # 1-indexed line number
      end
    end

    context 'when multiple ClaudeService.call invocations exist' do
      let(:file_content) do
        <<~RUBY
          def method_one
            ClaudeService.call(model: :haiku, prompt: "first")
          end

          def method_two
            ClaudeService.call(model: :sonnet, prompt: "second")
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'tracks line numbers for all usages' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.length).to eq(2)
        expect(usages[0].line_number).to eq(2)
        expect(usages[1].line_number).to eq(6)
      end
    end
  end

  describe 'violation severity classification' do
    let(:file_path) { 'app/services/provider_conversation_handler.rb' }

    context 'when AI is used in critical_verify fixed_template flow' do
      let(:file_content) do
        <<~RUBY
          class ProviderConversationHandler
            def send_thank_you
              # Flow: P10-P14 - Thank you and review request
              ClaudeService.call(
                model: :haiku,
                prompt: "Generate thank you"
              )
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'assigns critical severity for P10-P14' do
        violations = analyzer.call
        expect(violations).not_to be_empty

        violation = violations.first
        expect(violation.flow_id).to eq('P10-P14')
        expect(violation.severity).to eq(:critical)
        expect(violation.type).to eq(:improper_generation)
      end
    end

    context 'when wrong model is used for generation' do
      let(:file_path) { 'app/services/test_service.rb' }
      let(:file_content) do
        <<~RUBY
          class TestService
            def generate_bio
              # P6A: Generate provider bio
              ClaudeService.call(
                model: :haiku,
                prompt: "Generate bio"
              )
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'assigns minor severity for wrong model' do
        violations = analyzer.call
        expect(violations).not_to be_empty

        violation = violations.first
        expect(violation.type).to eq(:wrong_model)
        expect(violation.severity).to eq(:minor)
      end
    end
  end

  describe 'error handling' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when file read raises an error' do
      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_raise(StandardError, 'Read error')
      end

      it 'handles error gracefully and returns empty array' do
        result = analyzer.analyze_file(file_path)
        expect(result).to eq([])
      end
    end

    context 'when analyzing malformed Ruby code' do
      let(:file_content) do
        <<~RUBY
          def broken_method(
            ClaudeService.call(model: :haiku
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'does not crash and returns usages it can detect' do
        expect { analyzer.analyze_file(file_path) }.not_to raise_error
      end
    end
  end

  describe 'missing AI detection' do
    context 'when include_missing_ai is true' do
      let(:file_path) { 'app/services/empty_service.rb' }
      let(:file_content) do
        <<~RUBY
          class EmptyService
            def some_method
              "no AI here"
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'detects missing AI usage for flows requiring AI' do
        violations = analyzer.call(include_missing_ai: true)

        # Should detect flows marked as :verify that need AI but weren't found
        missing_violations = violations.select { |v| v.type == :missing_extraction || v.type == :missing_interpretation }
        expect(missing_violations).not_to be_empty
      end
    end

    context 'when include_missing_ai is false' do
      let(:file_path) { 'app/services/empty_service.rb' }
      let(:file_content) do
        <<~RUBY
          class EmptyService
            def some_method
              "no AI here"
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'does not detect missing AI usage' do
        violations = analyzer.call(include_missing_ai: false)

        missing_violations = violations.select { |v| v.type == :missing_extraction || v.type == :missing_interpretation }
        expect(missing_violations).to be_empty
      end
    end
  end

  describe 'improper generation detection in extraction/interpretation flows' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when generation method is used in extraction flow' do
      let(:file_content) do
        <<~RUBY
          class TestService
            def generate_city_data
              # P3E: City extraction
              ClaudeService.call(
                model: :haiku,
                prompt: "Generate city name"
              )
            end
          end
        RUBY
      end

      before do
        full_path = Rails.root.join(file_path)
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(full_path).and_return(true)
        allow(File).to receive(:exist?).with(full_path.to_s).and_return(true)
        allow(File).to receive(:read).with(full_path.to_s).and_return(file_content)
        stub_const('ElisaAudit::AiUsageAnalyzer::SERVICE_FILES', [file_path])
      end

      it 'detects improper generation in extraction flow' do
        violations = analyzer.call
        expect(violations).not_to be_empty

        violation = violations.find { |v| v.type == :improper_generation }
        expect(violation).to be_present
        expect(violation.flow_id).to eq('P3E')
        expect(violation.severity).to eq(:moderate)
      end
    end
  end

  describe 'model parameter edge cases' do
    let(:file_path) { 'app/services/test_service.rb' }

    context 'when model parameter is not found' do
      let(:file_content) do
        <<~RUBY
          def some_method
            ClaudeService.call(
              prompt: "test"
            )
          end
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'returns nil for model_used' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.model_used).to be_nil
      end
    end

    context 'when model parameter is far from call line' do
      let(:file_content) do
        <<~RUBY
          ClaudeService.call(
            prompt: "line 2",
            options: {
              key1: "value1",
              key2: "value2",
              key3: "value3"
            },
            model: :sonnet
          )
        RUBY
      end

      before do
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:read).with(file_path).and_return(file_content)
      end

      it 'finds model parameter within search range' do
        usages = analyzer.analyze_file(file_path)
        expect(usages.first.model_used).to eq(:sonnet)
      end
    end
  end
end
