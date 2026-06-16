# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ElisaAudit::YamlInventoryGenerator do
  subject(:generator) { described_class.new }

  let(:yaml_path) { described_class::YAML_PATH }
  let(:output_path) { described_class::OUTPUT_PATH }

  describe '#call' do
    context 'when YAML file is valid' do
      let(:valid_yaml_content) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'onboarding' => {
                  'welcome' => '¡Hola! 👋 Soy Elisa...',
                  'name_prompt' => '¿Cómo te llamas?',
                  'greeting' => 'Mucho gusto, %{name} 👋'
                }
              },
              'client' => {
                'region_detection' => {
                  'prompt' => '¿En qué ciudad estás?',
                  'confirmation' => 'Perfecto, %{city} y %{state}'
                }
              }
            }
          }
        }
      end

      let(:raw_yaml_content) do
        <<~YAML
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "¡Hola! 👋 Soy Elisa..."
                  name_prompt: "¿Cómo te llamas?"
                  greeting: "Mucho gusto, %{name} 👋"
              client:
                region_detection:
                  prompt: "¿En qué ciudad estás?"
                  confirmation: "Perfecto, %{city} y %{state}"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml_content)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(valid_yaml_content)
      end

      it 'returns a hash with markdown, entries, and stats' do
        result = generator.call

        expect(result).to be_a(Hash)
        expect(result).to have_key(:markdown)
        expect(result).to have_key(:entries)
        expect(result).to have_key(:stats)
        expect(result).to have_key(:syntax_errors)
      end

      it 'extracts all message entries' do
        result = generator.call

        expect(result[:entries]).to be_an(Array)
        expect(result[:entries]).to all(be_a(ElisaAudit::MessageEntry))
        expect(result[:entries].length).to eq(5)
      end

      it 'generates markdown with proper structure' do
        result = generator.call
        markdown = result[:markdown]

        expect(markdown).to include('# Elisa Message Inventory')
        expect(markdown).to include('## Statistics')
        expect(markdown).to include('## Provider Messages (P1-P20)')
        expect(markdown).to include('## Client Messages (C1-C7)')
      end

      it 'calculates correct statistics' do
        result = generator.call
        stats = result[:stats]

        expect(stats[:total]).to eq(5)
        expect(stats[:provider]).to eq(3)
        expect(stats[:client]).to eq(2)
      end

      it 'includes message content in entries' do
        result = generator.call
        welcome_entry = result[:entries].find { |e| e.content.include?('¡Hola! 👋') }

        expect(welcome_entry).to be_present
        expect(welcome_entry.content).to eq('¡Hola! 👋 Soy Elisa...')
      end
    end

    context 'when parsing flow IDs from key structure' do
      let(:yaml_with_flows) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'onboarding' => {
                  'welcome' => 'Welcome message',
                  'decline_closing' => 'Decline message',
                  'name_prompt' => 'Name prompt',
                  'greeting' => 'Greeting with %{name}',
                  'city_prompt' => 'City prompt'
                }
              },
              'client' => {
                'region_detection' => {
                  'prompt' => 'Region prompt'
                },
                'appointment' => {
                  'confirmation' => 'Appointment confirmed'
                },
                'emergency' => {
                  'alert' => 'Emergency alert!'
                },
                'review' => {
                  'request' => 'Please review'
                }
              }
            }
          }
        }
      end

      let(:raw_yaml) do
        <<~YAML
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "Welcome message"
                  decline_closing: "Decline message"
                  name_prompt: "Name prompt"
                  greeting: "Greeting with %{name}"
                  city_prompt: "City prompt"
              client:
                region_detection:
                  prompt: "Region prompt"
                appointment:
                  confirmation: "Appointment confirmed"
                emergency:
                  alert: "Emergency alert!"
                review:
                  request: "Please review"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(yaml_with_flows)
      end

      it 'infers P1A flow ID from onboarding.welcome key' do
        result = generator.call
        welcome_entry = result[:entries].find { |e| e.yaml_key.include?('onboarding.welcome') }

        expect(welcome_entry.flow_id).to eq('P1A')
      end

      it 'infers P1B flow ID from decline key' do
        result = generator.call
        decline_entry = result[:entries].find { |e| e.yaml_key.include?('decline_closing') }

        expect(decline_entry.flow_id).to eq('P1B')
      end

      it 'infers P2A flow ID from name key' do
        result = generator.call
        name_entry = result[:entries].find { |e| e.yaml_key.include?('name_prompt') }

        expect(name_entry.flow_id).to eq('P2A')
      end

      it 'infers P2B flow ID from greeting key' do
        result = generator.call
        greeting_entry = result[:entries].find { |e| e.yaml_key.include?('greeting') }

        expect(greeting_entry.flow_id).to eq('P2B')
      end

      it 'infers P3E flow ID from city key' do
        result = generator.call
        city_entry = result[:entries].find { |e| e.yaml_key.include?('city_prompt') }

        expect(city_entry.flow_id).to eq('P3E')
      end

      it 'infers C2A flow ID from region_detection key' do
        result = generator.call
        region_entry = result[:entries].find { |e| e.yaml_key.include?('region_detection') }

        expect(region_entry.flow_id).to eq('C2A')
      end

      it 'infers C4A flow ID from appointment key' do
        result = generator.call
        appointment_entry = result[:entries].find { |e| e.yaml_key.include?('appointment') }

        expect(appointment_entry.flow_id).to eq('C4A')
      end

      it 'infers C5A flow ID from emergency key' do
        result = generator.call
        emergency_entry = result[:entries].find { |e| e.yaml_key.include?('emergency') }

        expect(emergency_entry.flow_id).to eq('C5A')
      end

      it 'infers C7A flow ID from review key' do
        result = generator.call
        review_entry = result[:entries].find { |e| e.yaml_key.include?('review') }

        expect(review_entry.flow_id).to eq('C7A')
      end
    end

    context 'when detecting interpolation variables' do
      let(:yaml_with_variables) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'messages' => {
                  'no_variables' => 'Simple message',
                  'one_variable' => 'Hello %{name}',
                  'multiple_variables' => 'Hi %{name} from %{city} at %{time}',
                  'duplicate_variables' => '%{name} and %{name} again'
                }
              }
            }
          }
        }
      end

      let(:raw_yaml) do
        <<~YAML
          es:
            elisa:
              provider:
                messages:
                  no_variables: "Simple message"
                  one_variable: "Hello %{name}"
                  multiple_variables: "Hi %{name} from %{city} at %{time}"
                  duplicate_variables: "%{name} and %{name} again"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(yaml_with_variables)
      end

      it 'detects messages with no variables' do
        result = generator.call
        entry = result[:entries].find { |e| e.content == 'Simple message' }

        expect(entry.variables).to be_empty
        expect(entry.has_variables?).to be false
      end

      it 'detects single variable' do
        result = generator.call
        entry = result[:entries].find { |e| e.content.include?('Hello') }

        expect(entry.variables).to eq(['name'])
        expect(entry.has_variables?).to be true
      end

      it 'detects multiple variables' do
        result = generator.call
        entry = result[:entries].find { |e| e.yaml_key.include?('multiple_variables') }

        expect(entry).to be_present
        expect(entry.variables).to contain_exactly('name', 'city', 'time')
      end

      it 'handles duplicate variables by deduplicating' do
        result = generator.call
        entry = result[:entries].find { |e| e.yaml_key.include?('duplicate_variables') }

        expect(entry).to be_present
        expect(entry.variables).to eq(['name'])
      end
    end

    context 'when handling YAML syntax errors' do
      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return("invalid: yaml: content")
        allow(YAML).to receive(:load_file).with(yaml_path)
          .and_raise(Psych::SyntaxError.new('file', 42, 5, 0, 'found unexpected :', 'context'))
      end

      it 'raises YamlParseError with line number' do
        expect { generator.call }
          .to raise_error(ElisaAudit::YamlParseError, /Invalid YAML syntax at line 42/)
      end

      it 'includes error details in message' do
        expect { generator.call }
          .to raise_error(ElisaAudit::YamlParseError, /found unexpected :/)
      end
    end

    context 'when handling missing file error' do
      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(false)
      end

      it 'raises YamlParseError with file not found message' do
        expect { generator.call }
          .to raise_error(ElisaAudit::YamlParseError, /File not found/)
      end

      it 'includes file path in error message' do
        expect { generator.call }
          .to raise_error(ElisaAudit::YamlParseError, /#{Regexp.escape(yaml_path.to_s)}/)
      end
    end

    context 'when handling multiline messages' do
      let(:yaml_with_multiline) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'messages' => {
                  'short' => 'Single line',
                  'multiline' => "First line\nSecond line\nThird line",
                  'with_variables' => "Hello %{name}\nWelcome to %{city}"
                }
              }
            }
          }
        }
      end

      let(:raw_yaml) do
        <<~YAML
          es:
            elisa:
              provider:
                messages:
                  short: "Single line"
                  multiline: |
                    First line
                    Second line
                    Third line
                  with_variables: |
                    Hello %{name}
                    Welcome to %{city}
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(yaml_with_multiline)
      end

      it 'preserves multiline content in entries' do
        result = generator.call
        multiline_entry = result[:entries].find { |e| e.content.include?('First line') }

        expect(multiline_entry.content).to include("\n")
        expect(multiline_entry.content).to include('Second line')
      end

      it 'normalizes multiline content in markdown table' do
        result = generator.call
        markdown = result[:markdown]

        # Multiline content should be normalized to single line in table
        expect(markdown).to include('First line Second line Third line')
      end

      it 'extracts variables from multiline messages' do
        result = generator.call
        entry = result[:entries].find { |e| e.content.include?('Welcome to') }

        expect(entry.variables).to contain_exactly('name', 'city')
      end
    end

    context 'when handling array structures' do
      let(:yaml_with_arrays) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'list_messages' => {
                  'options' => ['Option 1', 'Option 2', 'Option 3']
                }
              }
            }
          }
        }
      end

      let(:raw_yaml) do
        <<~YAML
          es:
            elisa:
              provider:
                list_messages:
                  options:
                    - "Option 1"
                    - "Option 2"
                    - "Option 3"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(yaml_with_arrays)
      end

      it 'extracts individual array items as separate entries' do
        result = generator.call

        option_entries = result[:entries].select { |e| e.content.start_with?('Option') }
        expect(option_entries.length).to eq(3)
      end

      it 'assigns array index to YAML keys' do
        result = generator.call

        entry = result[:entries].find { |e| e.content == 'Option 2' }
        expect(entry.yaml_key).to include('[1]')
      end
    end

    context 'when handling special characters and emojis' do
      let(:yaml_with_special_chars) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'messages' => {
                  'with_emoji' => '¡Hola! 👋 Welcome 🎉',
                  'with_accents' => 'Adiós, México, José',
                  'with_pipes' => 'Option A | Option B | Option C',
                  'with_newlines' => "Line 1\nLine 2"
                }
              }
            }
          }
        }
      end

      let(:raw_yaml) do
        <<~YAML
          es:
            elisa:
              provider:
                messages:
                  with_emoji: "¡Hola! 👋 Welcome 🎉"
                  with_accents: "Adiós, México, José"
                  with_pipes: "Option A | Option B | Option C"
                  with_newlines: "Line 1\\nLine 2"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(yaml_with_special_chars)
      end

      it 'preserves emojis in message content' do
        result = generator.call
        emoji_entry = result[:entries].find { |e| e.content.include?('👋') }

        expect(emoji_entry.content).to include('👋')
        expect(emoji_entry.content).to include('🎉')
      end

      it 'preserves Spanish accents and special characters' do
        result = generator.call
        accent_entry = result[:entries].find { |e| e.content.include?('Adiós') }

        expect(accent_entry.content).to eq('Adiós, México, José')
      end

      it 'escapes pipe characters in markdown table' do
        result = generator.call
        markdown = result[:markdown]

        # Pipes should be escaped to not break markdown table structure
        expect(markdown).to include('\\|')
      end
    end

    context 'when tracking line numbers' do
      let(:yaml_content) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'onboarding' => {
                  'welcome' => 'Welcome message',
                  'name_prompt' => 'Name prompt'
                }
              }
            }
          }
        }
      end

      let(:raw_yaml) do
        <<~YAML
          # Line 1: comment
          es:
            elisa:
              provider:
                onboarding:
                  welcome: "Welcome message"
                  name_prompt: "Name prompt"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(yaml_content)
      end

      it 'tracks line numbers for each message' do
        result = generator.call

        result[:entries].each do |entry|
          expect(entry.line_number).to be_a(Integer).or be_nil
        end
      end

      it 'includes line numbers in markdown table' do
        result = generator.call
        markdown = result[:markdown]

        expect(markdown).to match(/\| Line \|/)
      end
    end

    context 'when validating YAML syntax' do
      let(:yaml_with_syntax_issues) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'messages' => {
                  'good_message' => 'Hello %{name}',
                  'bad_interpolation' => 'Hello {{user}}'
                }
              }
            }
          }
        }
      end

      let(:raw_yaml_with_issues) do
        <<~YAML
          es:
            elisa:
              provider:
                messages:
                  good_message: "Hello %{name}"
                  bad_interpolation: "Hello {{user}}"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(raw_yaml_with_issues)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(yaml_with_syntax_issues)
      end

      it 'runs syntax validation and includes errors' do
        result = generator.call

        expect(result[:syntax_errors]).to be_an(Array)
        expect(result[:syntax_errors].length).to be >= 1
      end

      it 'detects incorrect interpolation syntax' do
        result = generator.call

        interpolation_error = result[:syntax_errors].find { |e| e.error_type == :interpolation }
        expect(interpolation_error).to be_present
      end

      it 'includes syntax errors in markdown output' do
        result = generator.call
        markdown = result[:markdown]

        expect(markdown).to include('YAML Syntax Validation')
      end
    end

    context 'when YAML has no syntax issues' do
      let(:clean_yaml) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'messages' => {
                  'welcome' => 'Hello %{name}',
                  'greeting' => 'Welcome to %{city}'
                }
              }
            }
          }
        }
      end

      let(:clean_raw_yaml) do
        <<~YAML
          es:
            elisa:
              provider:
                messages:
                  welcome: "Hello %{name}"
                  greeting: "Welcome to %{city}"
        YAML
      end

      before do
        allow(File).to receive(:exist?).with(yaml_path).and_return(true)
        allow(File).to receive(:read).with(yaml_path).and_return(clean_raw_yaml)
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(clean_yaml)
      end

      it 'returns empty syntax errors array' do
        result = generator.call

        expect(result[:syntax_errors]).to be_empty
      end

      it 'shows success message in markdown' do
        result = generator.call
        markdown = result[:markdown]

        expect(markdown).to include('No syntax errors detected')
      end
    end
  end

  describe '#save_to_file' do
    let(:markdown_content) { "# Test Markdown\n\nContent here" }

    before do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    it 'creates output directory if needed' do
      generator.save_to_file(markdown_content)

      expect(FileUtils).to have_received(:mkdir_p).with(File.dirname(output_path))
    end

    it 'writes markdown content to file' do
      generator.save_to_file(markdown_content)

      expect(File).to have_received(:write).with(output_path, markdown_content)
    end

    it 'returns the output path' do
      result = generator.save_to_file(markdown_content)

      expect(result).to eq(output_path.to_s)
    end
  end
end
