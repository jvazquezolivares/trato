# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ElisaAudit::ListMessageValidator do
  describe '#call' do
    subject(:validator) { described_class.new }

    let(:yaml_path) { Rails.root.join('config', 'locales', 'elisa_es.yml') }

    context 'when all List Messages have valid structure' do
      let(:valid_yaml_data) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'list_messages' => {
                  'decline_reasons' => {
                    'title' => '¿Por qué no por ahora?',
                    'body' => 'Me ayudaría saber qué te detiene',
                    'button' => 'Ver opciones',
                    'options' => [
                      'Estoy muy ocupado',
                      'No entiendo qué es',
                      'No sé si vale pena'
                    ]
                  },
                  'price_range' => {
                    'title' => 'Rango de precio',
                    'body' => '¿Cuánto cobras por una visita de diagnóstico?',
                    'button' => 'Ver opciones',
                    'options' => [
                      '$100–200 MXN',
                      '$200–400 MXN',
                      '$400–600 MXN',
                      'Más de $600 MXN'
                    ]
                  },
                  'experience' => {
                    'title' => 'Años de experiencia',
                    'body' => '¿Cuántos años llevas trabajando en tu oficio?',
                    'button' => 'Ver opciones',
                    'options' => [
                      '1–3 años',
                      '4–6 años',
                      '7–10 años',
                      'Más de 10 años'
                    ]
                  },
                  'financial_summary' => {
                    'title' => '¿Qué quieres ver?',
                    'body' => 'Puedo mostrarte un resumen de tus finanzas',
                    'button' => 'Ver opciones',
                    'options' => [
                      'Ver ingresos',
                      'Ver gastos',
                      'Ver cobros',
                      'No, gracias'
                    ]
                  }
                }
              },
              'client' => {
                'list_messages' => {
                  'ratings' => {
                    'title' => '¿Cómo calificarías el trabajo?',
                    'body' => 'Tu opinión ayuda a otros clientes',
                    'button' => 'Ver opciones',
                    'options' => [
                      '⭐⭐⭐⭐⭐ Excelente',
                      '⭐⭐⭐⭐ Muy bueno',
                      '⭐⭐⭐ Bueno',
                      '⭐⭐ Regular',
                      '⭐ Malo'
                    ]
                  }
                }
              }
            }
          }
        }
      end

      before do
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(valid_yaml_data)
      end

      it 'returns all valid List Messages' do
        result = validator.call

        expect(result[:list_messages].count).to eq(5)
        expect(result[:malformed].count).to eq(0)
        expect(result[:stats][:total]).to eq(5)
        expect(result[:stats][:valid]).to eq(5)
        expect(result[:stats][:malformed]).to eq(0)
      end

      it 'extracts P1B decline reasons correctly' do
        result = validator.call

        p1b = result[:list_messages].find { |lm| lm.flow_id == 'P1B' }
        expect(p1b).to be_present
        expect(p1b.title).to eq('¿Por qué no por ahora?')
        expect(p1b.body).to eq('Me ayudaría saber qué te detiene')
        expect(p1b.button).to eq('Ver opciones')
        expect(p1b.options.count).to eq(3)
        expect(p1b.options_count).to eq(3)
      end

      it 'extracts P4 price range correctly' do
        result = validator.call

        p4 = result[:list_messages].find { |lm| lm.flow_id == 'P4' }
        expect(p4).to be_present
        expect(p4.title).to eq('Rango de precio')
        expect(p4.options.count).to eq(4)
        expect(p4.options).to include('$100–200 MXN')
      end

      it 'extracts P5 experience correctly' do
        result = validator.call

        p5 = result[:list_messages].find { |lm| lm.flow_id == 'P5' }
        expect(p5).to be_present
        expect(p5.title).to eq('Años de experiencia')
        expect(p5.options.count).to eq(4)
        expect(p5.options).to include('1–3 años')
      end

      it 'extracts P17 financial summary correctly' do
        result = validator.call

        p17 = result[:list_messages].find { |lm| lm.flow_id == 'P17' }
        expect(p17).to be_present
        expect(p17.title).to eq('¿Qué quieres ver?')
        expect(p17.options.count).to eq(4)
      end

      it 'extracts C7A ratings correctly' do
        result = validator.call

        c7a = result[:list_messages].find { |lm| lm.flow_id == 'C7A' }
        expect(c7a).to be_present
        expect(c7a.title).to eq('¿Cómo calificarías el trabajo?')
        expect(c7a.options.count).to eq(5)
        expect(c7a.options).to include('⭐⭐⭐⭐⭐ Excelente')
      end
    end

    context 'when a List Message is missing from YAML' do
      let(:incomplete_yaml_data) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'list_messages' => {
                  'decline_reasons' => {
                    'title' => '¿Por qué no por ahora?',
                    'body' => 'Me ayudaría saber qué te detiene',
                    'button' => 'Ver opciones',
                    'options' => ['Estoy muy ocupado']
                  }
                  # P4 price_range is missing
                }
              },
              'client' => {
                'list_messages' => {
                  # C7A ratings is missing
                }
              }
            }
          }
        }
      end

      before do
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(incomplete_yaml_data)
      end

      it 'flags missing List Messages as malformed' do
        result = validator.call

        expect(result[:list_messages].count).to eq(1) # Only P1B found
        expect(result[:malformed].count).to eq(4) # P4, P5, P17, C7A missing
        expect(result[:stats][:malformed]).to eq(4)
      end

      it 'reports missing P4 price range' do
        result = validator.call

        p4_malformed = result[:malformed].find { |m| m.flow_id == 'P4' }
        expect(p4_malformed).to be_present
        expect(p4_malformed.error).to include('not found')
      end

      it 'reports missing C7A ratings' do
        result = validator.call

        c7a_malformed = result[:malformed].find { |m| m.flow_id == 'C7A' }
        expect(c7a_malformed).to be_present
        expect(c7a_malformed.error).to include('not found')
      end
    end

    context 'when a List Message is missing required fields' do
      let(:malformed_yaml_data) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'list_messages' => {
                  'decline_reasons' => {
                    'title' => '¿Por qué no por ahora?',
                    # Missing body, button, options
                  },
                  'price_range' => {
                    'title' => 'Rango de precio',
                    'body' => '¿Cuánto cobras?',
                    'button' => 'Ver opciones'
                    # Missing options array
                  },
                  'experience' => {
                    'title' => 'Años de experiencia',
                    'body' => '¿Cuántos años llevas?',
                    'button' => 'Ver opciones',
                    'options' => []
                    # Empty options array
                  },
                  'financial_summary' => {
                    'title' => '¿Qué quieres ver?',
                    'body' => 'Puedo mostrarte un resumen',
                    'button' => 'Ver opciones',
                    'options' => [
                      'Ver ingresos',
                      'Ver gastos'
                    ]
                  }
                }
              },
              'client' => {
                'list_messages' => {
                  'ratings' => {
                    'title' => '¿Cómo calificarías?',
                    'body' => 'Tu opinión ayuda',
                    'button' => 'Ver opciones',
                    'options' => [
                      '⭐⭐⭐⭐⭐ Excelente',
                      '⭐⭐⭐⭐ Muy bueno'
                    ]
                  }
                }
              }
            }
          }
        }
      end

      before do
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(malformed_yaml_data)
      end

      it 'flags P1B as malformed (missing body, button, options)' do
        result = validator.call

        p1b_malformed = result[:malformed].find { |m| m.flow_id == 'P1B' }
        expect(p1b_malformed).to be_present
        expect(p1b_malformed.error).to include('Missing required fields')
        expect(p1b_malformed.missing_fields).to include('body', 'button', 'options')
      end

      it 'flags P4 as malformed (missing options)' do
        result = validator.call

        p4_malformed = result[:malformed].find { |m| m.flow_id == 'P4' }
        expect(p4_malformed).to be_present
        expect(p4_malformed.error).to include('Missing required fields')
        expect(p4_malformed.missing_fields).to include('options')
      end

      it 'flags P5 as malformed (empty options array)' do
        result = validator.call

        p5_malformed = result[:malformed].find { |m| m.flow_id == 'P5' }
        expect(p5_malformed).to be_present
        expect(p5_malformed.error).to include('empty')
      end

      it 'accepts P17 and C7A as valid (all fields present)' do
        result = validator.call

        p17_valid = result[:list_messages].find { |lm| lm.flow_id == 'P17' }
        c7a_valid = result[:list_messages].find { |lm| lm.flow_id == 'C7A' }

        expect(p17_valid).to be_present
        expect(c7a_valid).to be_present
      end
    end

    context 'when List Message structure is not a hash' do
      let(:invalid_structure_yaml) do
        {
          'es' => {
            'elisa' => {
              'provider' => {
                'list_messages' => {
                  'decline_reasons' => 'Not a hash, just a string',
                  'price_range' => {
                    'title' => 'Rango de precio',
                    'body' => '¿Cuánto cobras?',
                    'button' => 'Ver opciones',
                    'options' => 'Not an array'
                  },
                  'experience' => {
                    'title' => 'Años de experiencia',
                    'body' => '¿Cuántos años llevas?',
                    'button' => 'Ver opciones',
                    'options' => [
                      '1–3 años',
                      '4–6 años'
                    ]
                  },
                  'financial_summary' => {
                    'title' => '¿Qué quieres ver?',
                    'body' => 'Resumen',
                    'button' => 'Ver opciones',
                    'options' => [
                      'Ver ingresos'
                    ]
                  }
                }
              },
              'client' => {
                'list_messages' => {
                  'ratings' => {
                    'title' => '¿Cómo calificarías?',
                    'body' => 'Tu opinión ayuda',
                    'button' => 'Ver opciones',
                    'options' => [
                      '⭐⭐⭐⭐⭐ Excelente'
                    ]
                  }
                }
              }
            }
          }
        }
      end

      before do
        allow(YAML).to receive(:load_file).with(yaml_path).and_return(invalid_structure_yaml)
      end

      it 'flags P1B as malformed (not a hash)' do
        result = validator.call

        p1b_malformed = result[:malformed].find { |m| m.flow_id == 'P1B' }
        expect(p1b_malformed).to be_present
        expect(p1b_malformed.error).to include('must be a hash')
      end

      it 'flags P4 as malformed (options not an array)' do
        result = validator.call

        p4_malformed = result[:malformed].find { |m| m.flow_id == 'P4' }
        expect(p4_malformed).to be_present
        expect(p4_malformed.error).to include('Options must be an array')
      end

      it 'accepts P5, P17, and C7A as valid' do
        result = validator.call

        p5_valid = result[:list_messages].find { |lm| lm.flow_id == 'P5' }
        p17_valid = result[:list_messages].find { |lm| lm.flow_id == 'P17' }
        c7a_valid = result[:list_messages].find { |lm| lm.flow_id == 'C7A' }

        expect(p5_valid).to be_present
        expect(p17_valid).to be_present
        expect(c7a_valid).to be_present
      end
    end

    context 'when YAML file does not exist' do
      before do
        allow(YAML).to receive(:load_file).with(yaml_path).and_raise(Errno::ENOENT)
      end

      it 'raises YamlParseError' do
        expect { validator.call }.to raise_error(ElisaAudit::YamlParseError, /not found/)
      end
    end

    context 'when YAML file has syntax errors' do
      before do
        allow(YAML).to receive(:load_file).with(yaml_path).and_raise(
          Psych::SyntaxError.new('file', 42, 0, 0, 'problem', 'context')
        )
      end

      it 'raises YamlParseError with line number' do
        expect { validator.call }.to raise_error(ElisaAudit::YamlParseError, /line 42/)
      end
    end
  end

  describe 'ListMessageEntry#formatted_options' do
    let(:entry) do
      ElisaAudit::ListMessageEntry.new(
        flow_id: 'P4',
        yaml_path: 'elisa.provider.list_messages.price_range',
        title: 'Rango de precio',
        body: '¿Cuánto cobras?',
        button: 'Ver opciones',
        options: ['$100–200 MXN', '$200–400 MXN', '$400–600 MXN'],
        options_count: 3
      )
    end

    it 'formats options as numbered list' do
      formatted = entry.formatted_options

      expect(formatted).to include('1. $100–200 MXN')
      expect(formatted).to include('2. $200–400 MXN')
      expect(formatted).to include('3. $400–600 MXN')
    end
  end
end
