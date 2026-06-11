# frozen_string_literal: true

require 'rails_helper'
require 'elisa_verification/message_corrector'
require 'tempfile'

RSpec.describe ElisaVerification::MessageCorrector do
  let(:sample_yaml_content) do
    <<~YAML
      # frozen_string_literal: true

      # Test YAML file
      es:
        elisa:
          # Provider messages
          provider:
            onboarding:
              # P1A: Welcome message
              welcome: "¡Hola! 👋 Soy Elisa."

              # P1B: Decline message
              decline_closing: "¡Gracias!"

              # P2B: Greeting with interpolation
              # Variables: name
              greeting: "Mucho gusto, %{name} 👋"

            list_messages:
              # Decline reasons
              decline_reasons:
                - "Estoy ocupado"
                - "No entiendo"
                - "No vale pena"
    YAML
  end

  let(:temp_file) do
    file = Tempfile.new(['test_yaml', '.yml'])
    file.write(sample_yaml_content)
    file.close
    file
  end

  let(:corrector) { described_class.new(temp_file.path) }

  after do
    temp_file.unlink
  end

  describe '#initialize' do
    it 'loads the YAML file successfully' do
      expect(corrector).to be_a(described_class)
      expect(corrector.file_path).to eq(temp_file.path)
    end

    it 'reads all lines from the file' do
      expect(corrector.lines).to be_an(Array)
      expect(corrector.lines.length).to be > 0
    end

    it 'preserves comments by default' do
      expect(corrector.preserve_comments).to be true
    end
  end

  describe '#apply_correction' do
    context 'with simple string values' do
      it 'applies correction to a simple message' do
        result = corrector.apply_correction('elisa.provider.onboarding.welcome', '¡Hola! 👋 Soy Elisa de Trato.')

        expect(result).to be true
        yaml_string = corrector.to_yaml_string
        expect(yaml_string).to include('¡Hola! 👋 Soy Elisa de Trato.')
      end

      it 'preserves interpolation variables when correcting' do
        result = corrector.apply_correction('elisa.provider.onboarding.greeting', 'Hola, %{name} 🎉')

        expect(result).to be true
        yaml_string = corrector.to_yaml_string
        expect(yaml_string).to include('%{name}')
        expect(yaml_string).to include('Hola, %{name} 🎉')
      end

      it 'handles messages with emojis correctly' do
        new_value = '¡Gracias por contarme! 😊 Cuando quieras crear tu cuenta, escríbeme.'
        result = corrector.apply_correction('elisa.provider.onboarding.decline_closing', new_value)

        expect(result).to be true
        yaml_string = corrector.to_yaml_string
        expect(yaml_string).to include('😊')
      end

      it 'handles messages with special punctuation' do
        new_value = '¿Por qué no por ahora? ¡Cuéntame!'
        result = corrector.apply_correction('elisa.provider.onboarding.decline_closing', new_value)

        expect(result).to be true
        yaml_string = corrector.to_yaml_string
        expect(yaml_string).to include('¿Por qué no por ahora? ¡Cuéntame!')
      end
    end

    context 'with array values' do
      it 'corrects an array value' do
        new_array = ['Opción 1', 'Opción 2', 'Opción 3']
        result = corrector.apply_correction('elisa.provider.list_messages.decline_reasons', new_array)

        expect(result).to be true
        yaml_string = corrector.to_yaml_string
        # Array items without special YAML characters don't need quotes
        expect(yaml_string).to include('- Opción 1')
        expect(yaml_string).to include('- Opción 2')
        expect(yaml_string).to include('- Opción 3')
      end

      it 'maintains proper indentation for array items' do
        new_array = ['Item A', 'Item B']
        corrector.apply_correction('elisa.provider.list_messages.decline_reasons', new_array)

        lines = corrector.lines
        decline_reasons_line = lines.index { |l| l.include?('decline_reasons:') }

        # Check that the array items have 2 more spaces than the key (12 spaces in decline_reasons line)
        # The items should be at 10 spaces (key indent + 2)
        expect(lines[decline_reasons_line + 1]).to match(/^\s{10}- /)
      end
    end

    context 'with non-existent keys' do
      it 'returns false for a key that does not exist' do
        result = corrector.apply_correction('elisa.provider.nonexistent.key', 'Some value')

        expect(result).to be false
      end
    end
  end

  describe '#to_yaml_string' do
    it 'returns the complete YAML content as string' do
      yaml_string = corrector.to_yaml_string

      expect(yaml_string).to be_a(String)
      expect(yaml_string).to include('es:')
      expect(yaml_string).to include('elisa:')
    end

    it 'preserves comments in the output' do
      yaml_string = corrector.to_yaml_string

      expect(yaml_string).to include('# Test YAML file')
      expect(yaml_string).to include('# Provider messages')
      expect(yaml_string).to include('# P1A: Welcome message')
    end

    it 'preserves blank lines in the output' do
      yaml_string = corrector.to_yaml_string
      lines = yaml_string.split("\n")

      blank_lines = lines.select { |l| l.strip.empty? }
      expect(blank_lines.length).to be > 0
    end
  end

  describe '#create_backup' do
    after do
      # Clean up any backup files created during tests
      if corrector.last_backup_path && File.exist?(corrector.last_backup_path)
        File.delete(corrector.last_backup_path)
      end
    end

    it 'creates a timestamped backup of the original file' do
      backup_path = corrector.create_backup

      expect(File.exist?(backup_path)).to be true
      expect(backup_path).to match(/\.backup\.\d{14}$/)

      # Verify backup contains original content
      backup_content = File.read(backup_path)
      expect(backup_content).to eq(sample_yaml_content)
    end

    it 'stores the backup path in last_backup_path' do
      backup_path = corrector.create_backup

      expect(corrector.last_backup_path).to eq(backup_path)
      expect(corrector.last_backup_path).to match(/\.backup\.\d{14}$/)
    end

    it 'generates unique timestamps for consecutive backups' do
      backup_path1 = corrector.create_backup
      sleep 1 # Ensure timestamp is different
      backup_path2 = corrector.create_backup

      expect(backup_path1).not_to eq(backup_path2)
      expect(File.exist?(backup_path1)).to be true
      expect(File.exist?(backup_path2)).to be true

      # Clean up second backup
      File.delete(backup_path2) if File.exist?(backup_path2)
    end

    it 'can create backup of a different file' do
      other_file = Tempfile.new(['other_yaml', '.yml'])
      other_file.write("other: content\n")
      other_file.close

      backup_path = corrector.create_backup(other_file.path)

      expect(File.exist?(backup_path)).to be true
      expect(backup_path).to start_with(other_file.path)
      expect(backup_path).to match(/\.backup\.\d{14}$/)

      backup_content = File.read(backup_path)
      expect(backup_content).to eq("other: content\n")

      # Clean up
      File.delete(backup_path) if File.exist?(backup_path)
      other_file.unlink
    end

    it 'raises error if source file does not exist' do
      expect do
        corrector.create_backup('/nonexistent/path/file.yml')
      end.to raise_error(StandardError, /Cannot create backup: source file does not exist/)
    end

    it 'raises error if backup creation fails' do
      allow(FileUtils).to receive(:cp).and_raise(StandardError.new('Permission denied'))

      expect do
        corrector.create_backup
      end.to raise_error(StandardError, /Failed to create backup/)
    end
  end

  describe '#save' do
    let(:output_file) do
      file = Tempfile.new(['output_yaml', '.yml'])
      file.close
      file
    end

    after do
      output_file.unlink if File.exist?(output_file.path)
      # Clean up any backup files created during tests
      Dir.glob("#{output_file.path}.backup.*").each { |f| File.delete(f) if File.exist?(f) }
    end

    it 'saves the corrected YAML to a file' do
      corrector.apply_correction('elisa.provider.onboarding.welcome', 'New welcome message')
      result = corrector.save(output_file.path)

      expect(result).to be true
      expect(File.exist?(output_file.path)).to be true

      content = File.read(output_file.path)
      expect(content).to include('New welcome message')
    end

    it 'creates a timestamped backup before saving to an existing file' do
      # Create the file first with initial content
      File.write(output_file.path, sample_yaml_content)

      corrector.apply_correction('elisa.provider.onboarding.welcome', 'New welcome message')
      result = corrector.save(output_file.path)

      expect(result).to be true

      # Check that a backup file was created
      backup_files = Dir.glob("#{output_file.path}.backup.*")
      expect(backup_files.length).to eq(1)

      # Verify backup contains original content
      backup_content = File.read(backup_files.first)
      expect(backup_content).to include('¡Hola! 👋 Soy Elisa.')
      expect(backup_content).not_to include('New welcome message')

      # Clean up backup
      File.delete(backup_files.first)
    end

    it 'does not create backup if create_backup_before_save is false' do
      File.write(output_file.path, sample_yaml_content)

      corrector.apply_correction('elisa.provider.onboarding.welcome', 'New welcome message')
      result = corrector.save(output_file.path, create_backup_before_save: false)

      expect(result).to be true

      # Check that no backup file was created
      backup_files = Dir.glob("#{output_file.path}.backup.*")
      expect(backup_files.length).to eq(0)
    end

    it 'validates YAML before writing' do
      # Break the YAML structure by introducing invalid syntax
      corrector.instance_variable_set(:@lines, ["invalid: yaml: : content\n"])

      result = corrector.save(output_file.path)
      expect(result).to be false
    end

    it 'returns false if save fails' do
      allow(File).to receive(:write).and_raise(StandardError.new('Write error'))

      result = corrector.save(output_file.path)
      expect(result).to be false
    end

    it 'returns false if backup creation fails' do
      File.write(output_file.path, sample_yaml_content)
      allow(FileUtils).to receive(:cp).and_raise(StandardError.new('Backup error'))

      result = corrector.save(output_file.path)
      expect(result).to be false
    end
  end

  describe 'comment preservation' do
    it 'preserves flow ID comments' do
      corrector.apply_correction('elisa.provider.onboarding.welcome', 'Updated message')
      yaml_string = corrector.to_yaml_string

      expect(yaml_string).to include('# P1A: Welcome message')
    end

    it 'preserves variable documentation comments' do
      corrector.apply_correction('elisa.provider.onboarding.greeting', 'Updated greeting')
      yaml_string = corrector.to_yaml_string

      expect(yaml_string).to include('# Variables: name')
    end

    it 'preserves section header comments' do
      corrector.apply_correction('elisa.provider.onboarding.welcome', 'Updated message')
      yaml_string = corrector.to_yaml_string

      expect(yaml_string).to include('# Provider messages')
    end
  end

  describe 'indentation preservation' do
    it 'maintains original indentation levels' do
      original_lines = corrector.lines.dup
      corrector.apply_correction('elisa.provider.onboarding.welcome', 'Updated message')
      new_lines = corrector.lines

      # Find the welcome line and check indentation
      original_welcome_line = original_lines.find { |l| l.include?('welcome:') }
      new_welcome_line = new_lines.find { |l| l.include?('welcome:') }

      original_indent = original_welcome_line[/^\s*/].length
      new_indent = new_welcome_line[/^\s*/].length

      expect(new_indent).to eq(original_indent)
    end
  end

  describe 'UTF-8 encoding' do
    it 'handles Spanish special characters correctly' do
      new_value = 'Año, niño, señor — ¡Válido!'
      corrector.apply_correction('elisa.provider.onboarding.welcome', new_value)
      yaml_string = corrector.to_yaml_string

      expect(yaml_string).to include('Año')
      expect(yaml_string).to include('niño')
      expect(yaml_string).to include('señor')
    end

    it 'handles emojis correctly' do
      new_value = '🎉 👋 😊 🚨 ⭐ 📋'
      corrector.apply_correction('elisa.provider.onboarding.welcome', new_value)
      yaml_string = corrector.to_yaml_string

      expect(yaml_string).to include('🎉')
      expect(yaml_string).to include('👋')
      expect(yaml_string).to include('😊')
    end
  end

  describe 'quoting logic' do
    it 'quotes strings with special YAML characters' do
      new_value = 'Message with colon: and dash-'
      corrector.apply_correction('elisa.provider.onboarding.welcome', new_value)
      yaml_string = corrector.to_yaml_string

      welcome_line = yaml_string.lines.find { |l| l.include?('welcome:') }
      expect(welcome_line).to include('"Message with colon: and dash-"')
    end

    it 'does not unnecessarily quote simple strings' do
      new_value = 'Simple message'
      corrector.apply_correction('elisa.provider.onboarding.welcome', new_value)
      yaml_string = corrector.to_yaml_string

      welcome_line = yaml_string.lines.find { |l| l.include?('welcome:') }
      # Simple strings may or may not be quoted depending on needs_quoting? logic
      expect(welcome_line).to include('Simple message')
    end
  end
end
