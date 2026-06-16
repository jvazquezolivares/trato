# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ElisaAudit::WhatsAppTemplateDetector do
  subject(:detector) { described_class.new }

  let(:yaml_content) do
    {
      'es' => {
        'elisa' => {
          'provider' => {
            'morning_summary' => {
              'with_tasks_header' => 'Buenos días, %{name} 👋',
              'with_tasks_footer' => '¡Que tengas un excelente día!',
              'no_tasks' => 'Buenos días, %{name}! No tienes pendientes hoy.'
            }
          },
          'client' => {
            'appointment' => {
              'notification_header' => 'Nueva cita programada:',
              'notification_footer' => '¿Te parece bien?'
            },
            'review' => {
              'request' => 'Hola %{nombre_cliente}, ¿qué tal te fue?'
            }
          }
        }
      }
    }
  end

  before do
    allow(File).to receive(:exist?).with(described_class::YAML_PATH).and_return(true)
    allow(YAML).to receive(:load_file).with(described_class::YAML_PATH).and_return(yaml_content)
  end

  describe '#call' do
    context 'when detecting all proactive flows' do
      it 'generates requirements for all PROACTIVE_FLOWS' do
        requirements = detector.call
        flow_ids = requirements.map(&:flow_id).uniq

        expect(flow_ids).to include('P10-P14', 'P16', 'C4A', 'C4D', 'C4E', 'C7A', 'C7C')
      end

      it 'marks all templates as proactive' do
        requirements = detector.call

        expect(requirements).to all(have_attributes(is_proactive: true))
      end
    end

    context 'when YAML file does not exist' do
      before do
        allow(File).to receive(:exist?).with(described_class::YAML_PATH).and_return(false)
      end

      it 'raises YamlParseError' do
        expect { detector.call }.to raise_error(
          ElisaAudit::YamlParseError,
          /File not found/
        )
      end
    end

    context 'when YAML has syntax errors' do
      before do
        allow(YAML).to receive(:load_file).and_raise(
          Psych::SyntaxError.new('file', 42, 0, 0, 'problem', 'context')
        )
      end

      it 'raises YamlParseError with line number' do
        expect { detector.call }.to raise_error(
          ElisaAudit::YamlParseError,
          /Invalid YAML syntax at line 42/
        )
      end
    end
  end

  describe 'template formatting for Meta API (Task 5.3)' do
    let(:requirements) { detector.call }

    context 'Ruby interpolation to WhatsApp template syntax conversion' do
      it 'converts %{name} to {{name}} syntax' do
        p16_templates = requirements.select { |r| r.flow_id == 'P16' }

        p16_templates.each do |template|
          expect(template.message_text).not_to match(/%\{[^}]+\}/)
          expect(template.message_text).to match(/\{\{[^}]+\}\}/) if template.variables.any?
        end
      end

      it 'preserves emojis and special characters during conversion' do
        p16_templates = requirements.select { |r| r.flow_id == 'P16' }
        with_tasks = p16_templates.find { |t| t.template_name.include?('with_tasks') }

        expect(with_tasks.message_text).to include('👋')
      end

      it 'handles multiline messages correctly' do
        c4a_templates = requirements.select { |r| r.flow_id == 'C4A' }
        provider_template = c4a_templates.find { |t| t.template_name.include?('provider') }

        expect(provider_template.message_text).to include("\n")
      end
    end

    context 'variable documentation for Meta API' do
      it 'includes variable type for each placeholder' do
        requirements.each do |req|
          req.variables.each do |var|
            expect(var).to have_key(:type)
            expect(var[:type]).to eq('text')
          end
        end
      end

      it 'includes example value for each variable' do
        requirements.each do |req|
          req.variables.each do |var|
            expect(var).to have_key(:example)
            expect(var[:example]).to be_a(String)
            expect(var[:example]).not_to be_empty
          end
        end
      end

      it 'includes variable name for each placeholder' do
        requirements.each do |req|
          req.variables.each do |var|
            expect(var).to have_key(:name)
            expect(var[:name]).to be_a(String)
            expect(var[:name]).not_to be_empty
          end
        end
      end

      it 'generates contextual examples based on variable name' do
        p16_templates = requirements.select { |r| r.flow_id == 'P16' }
        name_var = p16_templates.first.variables.find { |v| v[:name] == 'name' }

        expect(name_var[:example]).to eq('Miguel')
      end
    end

    context 'exact template text with proper variable placeholders' do
      it 'replaces all Rails i18n variables with WhatsApp template variables' do
        requirements.each do |req|
          # Should not contain Rails syntax
          expect(req.message_text).not_to match(/%\{[^}]+\}/)

          # Should contain WhatsApp syntax if variables exist
          if req.variables.any?
            req.variables.each do |var|
              expect(req.message_text).to include("{{#{var[:name]}}}")
            end
          end
        end
      end

      it 'maintains exact message structure from YAML' do
        p16_templates = requirements.select { |r| r.flow_id == 'P16' }
        no_tasks_template = p16_templates.find { |t| t.template_name.include?('no_tasks') }

        # Should start with converted greeting
        expect(no_tasks_template.message_text).to start_with('Buenos días, {{name}}!')
      end

      it 'includes all required text content beyond variables' do
        p16_templates = requirements.select { |r| r.flow_id == 'P16' }

        p16_templates.each do |template|
          # Message should have substantial content, not just variables
          text_without_vars = template.message_text.gsub(/\{\{[^}]+\}\}/, '')
          expect(text_without_vars.length).to be > 10
        end
      end
    end

    context 'Meta API approval process compatibility' do
      it 'categorizes all templates as UTILITY (not MARKETING)' do
        requirements.each do |req|
          expect(req.category).to eq('UTILITY')
        end
      end

      it 'includes flow_id reference for each template' do
        requirements.each do |req|
          expect(req.flow_id).to be_present
          expect(req.flow_id).to match(/^(P|C)\d+/)
        end
      end

      it 'provides unique template_name for each requirement' do
        template_names = requirements.map(&:template_name)

        expect(template_names.uniq.length).to eq(template_names.length)
      end

      it 'includes yaml_key reference for traceability' do
        requirements.each do |req|
          expect(req.yaml_key).to be_present
        end
      end

      it 'generates valid snake_case template names' do
        requirements.each do |req|
          expect(req.template_name).to match(/^[a-z][a-z0-9_]*$/)
        end
      end
    end
  end

  describe '#detect_template_for_flow' do
    context 'P10-P14: Thank you + review request' do
      it 'generates template requirement' do
        requirements = detector.call
        p10_14 = requirements.find { |r| r.flow_id == 'P10-P14' }

        expect(p10_14).to be_present
        expect(p10_14.template_name).to eq('provider_thank_you_review_request')
        expect(p10_14.category).to eq('UTILITY')
      end

      it 'includes nombre_proveedor and nombre_cliente variables' do
        requirements = detector.call
        p10_14 = requirements.find { |r| r.flow_id == 'P10-P14' }

        variable_names = p10_14.variables.map { |v| v[:name] }
        expect(variable_names).to include('nombre_proveedor', 'nombre_cliente')
      end

      it 'converts message to WhatsApp template syntax' do
        requirements = detector.call
        p10_14 = requirements.find { |r| r.flow_id == 'P10-P14' }

        expect(p10_14.message_text).to include('{{nombre_proveedor}}')
        expect(p10_14.message_text).to include('{{nombre_cliente}}')
      end
    end

    context 'P16: Morning summary' do
      it 'generates two template variants (with tasks and no tasks)' do
        requirements = detector.call
        p16_templates = requirements.select { |r| r.flow_id == 'P16' }

        expect(p16_templates.length).to eq(2)

        template_names = p16_templates.map(&:template_name)
        expect(template_names).to include(
          'provider_morning_summary_with_tasks',
          'provider_morning_summary_no_tasks'
        )
      end

      it 'includes lista_tareas variable in with_tasks variant' do
        requirements = detector.call
        with_tasks = requirements.find do |r|
          r.flow_id == 'P16' && r.template_name.include?('with_tasks')
        end

        variable_names = with_tasks.variables.map { |v| v[:name] }
        expect(variable_names).to include('lista_tareas')
      end

      it 'extracts variables from YAML content' do
        requirements = detector.call
        p16_templates = requirements.select { |r| r.flow_id == 'P16' }

        p16_templates.each do |template|
          variable_names = template.variables.map { |v| v[:name] }
          expect(variable_names).to include('name')
        end
      end
    end

    context 'C4A: Appointment notifications' do
      it 'generates two templates (provider and client)' do
        requirements = detector.call
        c4a_templates = requirements.select { |r| r.flow_id == 'C4A' }

        expect(c4a_templates.length).to eq(2)

        template_names = c4a_templates.map(&:template_name)
        expect(template_names).to include(
          'appointment_notification_to_provider',
          'appointment_confirmation_to_client'
        )
      end

      it 'includes appointment details variables in provider notification' do
        requirements = detector.call
        provider_template = requirements.find do |r|
          r.flow_id == 'C4A' && r.template_name.include?('provider')
        end

        variable_names = provider_template.variables.map { |v| v[:name] }
        expect(variable_names).to include(
          'nombre_cliente', 'telefono_cliente', 'tipo_servicio',
          'direccion', 'fecha', 'duracion'
        )
      end

      it 'includes basic variables in client confirmation' do
        requirements = detector.call
        client_template = requirements.find do |r|
          r.flow_id == 'C4A' && r.template_name.include?('client')
        end

        variable_names = client_template.variables.map { |v| v[:name] }
        expect(variable_names).to include('nombre_proveedor', 'fecha')
      end
    end

    context 'C4D: Appointment reminders' do
      it 'generates four reminder templates' do
        requirements = detector.call
        c4d_templates = requirements.select { |r| r.flow_id == 'C4D' }

        expect(c4d_templates.length).to eq(4)

        template_names = c4d_templates.map(&:template_name)
        expect(template_names).to include(
          'appointment_reminder_1h',
          'appointment_reminder_now',
          'appointment_reminder_waiting',
          'appointment_conciliatory_to_client'
        )
      end

      it 'includes common variables in all reminders' do
        requirements = detector.call
        c4d_templates = requirements.select { |r| r.flow_id == 'C4D' }

        c4d_templates.each do |template|
          variable_names = template.variables.map { |v| v[:name] }
          expect(variable_names).to include('nombre_proveedor', 'nombre_cliente')
        end
      end
    end

    context 'C4E: Appointment cancellation' do
      it 'generates cancellation notice template' do
        requirements = detector.call
        c4e = requirements.find { |r| r.flow_id == 'C4E' }

        expect(c4e).to be_present
        expect(c4e.template_name).to eq('appointment_cancellation_notice')
      end

      it 'includes client, provider, and date variables' do
        requirements = detector.call
        c4e = requirements.find { |r| r.flow_id == 'C4E' }

        variable_names = c4e.variables.map { |v| v[:name] }
        expect(variable_names).to include('nombre_cliente', 'nombre_proveedor', 'fecha')
      end
    end

    context 'C7A: Review request first attempt' do
      it 'generates review request template' do
        requirements = detector.call
        c7a = requirements.find { |r| r.flow_id == 'C7A' }

        expect(c7a).to be_present
        expect(c7a.template_name).to eq('review_request_first_attempt')
      end

      it 'includes client and provider name variables' do
        requirements = detector.call
        c7a = requirements.find { |r| r.flow_id == 'C7A' }

        variable_names = c7a.variables.map { |v| v[:name] }
        expect(variable_names).to include('nombre_cliente', 'nombre_proveedor')
      end
    end

    context 'C7C: Review request second attempt' do
      it 'generates retry review request template' do
        requirements = detector.call
        c7c = requirements.find { |r| r.flow_id == 'C7C' }

        expect(c7c).to be_present
        expect(c7c.template_name).to eq('review_request_second_attempt')
      end

      it 'includes client and provider name variables' do
        requirements = detector.call
        c7c = requirements.find { |r| r.flow_id == 'C7C' }

        variable_names = c7c.variables.map { |v| v[:name] }
        expect(variable_names).to include('nombre_cliente', 'nombre_proveedor')
      end
    end
  end

  describe '#convert_to_template_syntax' do
    it 'converts %{name} to {{name}}' do
      message = 'Hola %{name}, bienvenido'
      result = detector.send(:convert_to_template_syntax, message)

      expect(result).to eq('Hola {{name}}, bienvenido')
    end

    it 'converts multiple variables in single message' do
      message = 'Hola %{name} de %{ciudad}, tu teléfono es %{phone}'
      result = detector.send(:convert_to_template_syntax, message)

      expect(result).to eq('Hola {{name}} de {{ciudad}}, tu teléfono es {{phone}}')
    end

    it 'preserves emojis during conversion' do
      message = 'Hola %{name} 👋🏼'
      result = detector.send(:convert_to_template_syntax, message)

      expect(result).to eq('Hola {{name}} 👋🏼')
    end

    it 'preserves special characters during conversion' do
      message = '¿Hola %{name}! ¿Cómo estás?'
      result = detector.send(:convert_to_template_syntax, message)

      expect(result).to eq('¿Hola {{name}}! ¿Cómo estás?')
    end

    it 'handles messages with no variables' do
      message = 'Hola, bienvenido'
      result = detector.send(:convert_to_template_syntax, message)

      expect(result).to eq('Hola, bienvenido')
    end

    it 'handles nil input' do
      result = detector.send(:convert_to_template_syntax, nil)

      expect(result).to eq('')
    end

    it 'handles empty string' do
      result = detector.send(:convert_to_template_syntax, '')

      expect(result).to eq('')
    end
  end

  describe '#extract_variables_from_message' do
    it 'extracts single variable' do
      message = 'Hola %{name}'
      result = detector.send(:extract_variables_from_message, message)

      expect(result.length).to eq(1)
      expect(result.first[:name]).to eq('name')
      expect(result.first[:type]).to eq('text')
      expect(result.first[:example]).to be_present
    end

    it 'extracts multiple variables' do
      message = 'Hola %{name} de %{ciudad}'
      result = detector.send(:extract_variables_from_message, message)

      expect(result.length).to eq(2)
      expect(result.map { |v| v[:name] }).to contain_exactly('name', 'ciudad')
    end

    it 'deduplicates repeated variables' do
      message = 'Hola %{name}, adiós %{name}'
      result = detector.send(:extract_variables_from_message, message)

      expect(result.length).to eq(1)
      expect(result.first[:name]).to eq('name')
    end

    it 'returns empty array for message with no variables' do
      message = 'Hola, bienvenido'
      result = detector.send(:extract_variables_from_message, message)

      expect(result).to eq([])
    end

    it 'returns empty array for nil message' do
      result = detector.send(:extract_variables_from_message, nil)

      expect(result).to eq([])
    end

    it 'returns empty array for empty message' do
      result = detector.send(:extract_variables_from_message, '')

      expect(result).to eq([])
    end
  end

  describe '#generate_example_for_variable' do
    it 'generates Miguel for name/nombre_proveedor/provider_name' do
      expect(detector.send(:generate_example_for_variable, 'name')).to eq('Miguel')
      expect(detector.send(:generate_example_for_variable, 'nombre_proveedor')).to eq('Miguel')
      expect(detector.send(:generate_example_for_variable, 'provider_name')).to eq('Miguel')
    end

    it 'generates María for nombre_cliente/client_name' do
      expect(detector.send(:generate_example_for_variable, 'nombre_cliente')).to eq('María')
      expect(detector.send(:generate_example_for_variable, 'client_name')).to eq('María')
    end

    it 'generates Veracruz for ciudad/city' do
      expect(detector.send(:generate_example_for_variable, 'ciudad')).to eq('Veracruz')
      expect(detector.send(:generate_example_for_variable, 'city')).to eq('Veracruz')
    end

    it 'generates phone number for phone/telefono' do
      expect(detector.send(:generate_example_for_variable, 'phone')).to eq('+52 229 123 4567')
      expect(detector.send(:generate_example_for_variable, 'telefono')).to eq('+52 229 123 4567')
    end

    it 'generates date format for fecha/date' do
      expect(detector.send(:generate_example_for_variable, 'fecha')).to eq('mañana a las 10:00 AM')
      expect(detector.send(:generate_example_for_variable, 'date')).to eq('mañana a las 10:00 AM')
    end

    it 'generates count for count' do
      expect(detector.send(:generate_example_for_variable, 'count')).to eq('3')
    end

    it 'generates rating for rating' do
      expect(detector.send(:generate_example_for_variable, 'rating')).to eq('5')
    end

    it 'generates default format for unknown variable' do
      result = detector.send(:generate_example_for_variable, 'unknown_var')

      expect(result).to eq('{{unknown_var}}')
    end
  end
end
