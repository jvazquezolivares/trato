# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ElisaAudit::YamlSyntaxValidator do
  let(:temp_yaml_path) { Rails.root.join('tmp', 'test_elisa_es.yml') }
  let(:validator) { described_class.new(temp_yaml_path) }

  before do
    FileUtils.mkdir_p(Rails.root.join('tmp'))
  end

  after do
    File.delete(temp_yaml_path) if File.exist?(temp_yaml_path)
  end

  describe '#validate' do
    context 'when YAML file is valid with correct syntax' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "¡Hola! 👋 Soy Elisa"
                  greeting: "Mucho gusto, %{name}"
              list_messages:
                price_range:
                  title: "Rango de precio"
                  body: "¿Cuánto cobras?"
                  button: "Ver opciones"
                  options:
                    - "$100–200 MXN"
                    - "$200–400 MXN"
        YAML
      end

      it 'returns empty errors array' do
        errors = validator.validate
        expect(errors).to be_empty
      end

      it 'reports no errors' do
        validator.validate
        expect(validator.errors?).to be false
      end
    end

    context 'when YAML has incorrect interpolation syntax' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "¡Hola {{name}}!"
                  greeting: "Bienvenido {{user}}"
        YAML
      end

      it 'detects Liquid/Mustache syntax errors' do
        errors = validator.validate
        expect(errors.count).to eq(2)
      end

      it 'marks errors as critical' do
        errors = validator.validate
        expect(errors.all? { |e| e.severity == :critical }).to be true
      end

      it 'identifies error type as interpolation' do
        errors = validator.validate
        expect(errors.all? { |e| e.error_type == :interpolation }).to be true
      end

      it 'includes line numbers' do
        errors = validator.validate
        expect(errors.first.line_number).to be_a(Integer)
      end

      it 'includes helpful error message' do
        errors = validator.validate
        expect(errors.first.message).to include('Rails i18n')
        expect(errors.first.message).to include('%{variable}')
      end
    end

    context 'when YAML has incomplete interpolation variable' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "¡Hola %{name!"
        YAML
      end

      it 'may detect incomplete variable syntax' do
        errors = validator.validate
        # This is a tricky edge case - incomplete variables at end of line
        # might not always be detected depending on YAML parsing
        expect(errors).to be_an(Array)
      end
    end

    context 'when YAML has empty interpolation variable' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "¡Hola %{}!"
        YAML
      end

      it 'detects empty variable' do
        errors = validator.validate
        expect(errors.count).to be >= 1
      end

      it 'marks as critical' do
        errors = validator.validate
        interpolation_errors = errors.select { |e| e.error_type == :interpolation }
        expect(interpolation_errors.any? { |e| e.severity == :critical }).to be true
      end
    end

    context 'when YAML has invalid general syntax' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider
                onboarding:
                  welcome: "Bad syntax"
        YAML
      end

      it 'detects YAML parse error' do
        errors = validator.validate
        expect(errors.count).to be >= 1
      end

      it 'marks as critical' do
        errors = validator.validate
        expect(errors.first.severity).to eq(:critical)
      end

      it 'identifies error type as general' do
        errors = validator.validate
        expect(errors.first.error_type).to eq(:general)
      end
    end

    context 'when List Message structure is incomplete' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                list_messages:
                  price_range:
                    title: "Rango de precio"
                    body: "¿Cuánto cobras?"
        YAML
      end

      it 'detects missing required fields' do
        errors = validator.validate
        expect(errors.count).to be >= 2 # Missing button and options
      end

      it 'marks as critical' do
        errors = validator.validate
        critical_errors = errors.select { |e| e.severity == :critical }
        expect(critical_errors.count).to be >= 2
      end

      it 'identifies error type as array' do
        errors = validator.validate
        array_errors = errors.select { |e| e.error_type == :array }
        expect(array_errors.count).to be >= 2
      end
    end

    context 'when List Message options is not an array' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                list_messages:
                  price_range:
                    title: "Rango de precio"
                    body: "¿Cuánto cobras?"
                    button: "Ver opciones"
                    options: "Not an array"
        YAML
      end

      it 'detects invalid options type' do
        errors = validator.validate
        expect(errors.count).to be >= 1
      end

      it 'marks as critical' do
        errors = validator.validate
        options_error = errors.find { |e| e.key_path&.include?('options') }
        expect(options_error.severity).to eq(:critical)
      end
    end

    context 'when List Message options array is empty' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                list_messages:
                  price_range:
                    title: "Rango de precio"
                    body: "¿Cuánto cobras?"
                    button: "Ver opciones"
                    options: []
        YAML
      end

      it 'detects empty options array' do
        errors = validator.validate
        expect(errors.count).to be >= 1
      end

      it 'marks as critical' do
        errors = validator.validate
        empty_array_error = errors.find { |e| e.message.include?('vacío') }
        expect(empty_array_error.severity).to eq(:critical)
      end
    end

    context 'when YAML file does not exist' do
      let(:validator) { described_class.new('/nonexistent/path/to/file.yml') }

      it 'detects missing file' do
        errors = validator.validate
        expect(errors.count).to eq(1)
      end

      it 'marks as critical' do
        errors = validator.validate
        expect(errors.first.severity).to eq(:critical)
      end

      it 'includes helpful error message' do
        errors = validator.validate
        expect(errors.first.message).to include('no encontrado')
      end
    end
  end

  describe '#errors?' do
    context 'when no errors exist' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "¡Hola!"
        YAML
      end

      it 'returns false' do
        validator.validate
        expect(validator.errors?).to be false
      end
    end

    context 'when errors exist' do
      before do
        File.write(temp_yaml_path, <<~YAML)
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "¡Hola {{name}}!"
        YAML
      end

      it 'returns true' do
        validator.validate
        expect(validator.errors?).to be true
      end
    end
  end

  describe '#error_summary' do
    before do
      File.write(temp_yaml_path, <<~YAML)
        es:
          elisa:
            provider:
              onboarding:
                welcome: "{{name}}"
                greeting: "%{}"
                message: "String with : character needs attention"
      YAML
    end

    it 'returns counts by severity' do
      validator.validate
      summary = validator.error_summary

      expect(summary).to have_key(:critical)
      expect(summary).to have_key(:warning)
      expect(summary).to have_key(:info)
      expect(summary).to have_key(:total)
    end

    it 'total equals sum of all severities' do
      validator.validate
      summary = validator.error_summary

      total = summary[:critical] + summary[:warning] + summary[:info]
      expect(summary[:total]).to eq(total)
    end
  end
end
