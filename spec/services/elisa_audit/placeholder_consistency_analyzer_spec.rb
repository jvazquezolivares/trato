# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/elisa_audit/placeholder_consistency_analyzer'
require_relative '../../../app/services/elisa_audit/data_models'

RSpec.describe ElisaAudit::PlaceholderConsistencyAnalyzer do
  describe '#call' do
    subject(:analyzer) { described_class.new(message_entries) }

    context 'when placeholders are consistent' do
      let(:message_entries) do
        [
          ElisaAudit::MessageEntry.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.onboarding.welcome',
            content: 'Hola %{provider_name}, bienvenido a Trato',
            line_number: 10,
            variables: ['provider_name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P2A',
            yaml_key: 'elisa.provider.onboarding.greeting',
            content: 'Gracias %{provider_name}, tu perfil está listo',
            line_number: 15,
            variables: ['provider_name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P3A',
            yaml_key: 'elisa.provider.onboarding.city',
            content: 'Trabajas en %{ciudad}',
            line_number: 20,
            variables: ['ciudad']
          )
        ]
      end

      it 'returns no inconsistencies' do
        result = analyzer.call
        expect(result[:inconsistencies]).to be_empty
      end

      it 'sets has_issues to false' do
        result = analyzer.call
        expect(result[:has_issues]).to be false
      end

      it 'collects all unique placeholders with frequency' do
        result = analyzer.call
        expect(result[:all_placeholders]).to eq(
          'provider_name' => 2,
          'ciudad' => 1
        )
      end

      it 'returns no recommendations' do
        result = analyzer.call
        expect(result[:recommendations]).to be_empty
      end
    end

    context 'when there are inconsistencies in provider name placeholders' do
      let(:message_entries) do
        [
          ElisaAudit::MessageEntry.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.onboarding.welcome',
            content: 'Hola %{name}, bienvenido',
            line_number: 10,
            variables: ['name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P2A',
            yaml_key: 'elisa.provider.onboarding.greeting',
            content: 'Gracias %{provider_name}',
            line_number: 15,
            variables: ['provider_name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P3A',
            yaml_key: 'elisa.provider.onboarding.complete',
            content: 'Perfecto %{nombre}',
            line_number: 20,
            variables: ['nombre']
          )
        ]
      end

      it 'detects provider name inconsistency' do
        result = analyzer.call
        expect(result[:inconsistencies].count).to eq(1)

        inconsistency = result[:inconsistencies].first
        expect(inconsistency[:concept]).to eq(:provider_name)
      end

      it 'identifies all variants used' do
        result = analyzer.call
        inconsistency = result[:inconsistencies].first

        expect(inconsistency[:variants]).to contain_exactly('name', 'provider_name', 'nombre')
      end

      it 'sets has_issues to true' do
        result = analyzer.call
        expect(result[:has_issues]).to be true
      end

      it 'generates recommendation for standardization' do
        result = analyzer.call
        expect(result[:recommendations]).not_to be_empty

        recommendation = result[:recommendations].first
        expect(recommendation).to include('Estandarizar')
        expect(recommendation).to include('provider_name')
      end

      it 'collects examples for each variant' do
        result = analyzer.call
        inconsistency = result[:inconsistencies].first

        expect(inconsistency[:examples]).to have_key('name')
        expect(inconsistency[:examples]).to have_key('provider_name')
        expect(inconsistency[:examples]).to have_key('nombre')

        # Verify examples contain expected data
        name_example = inconsistency[:examples]['name'].first
        expect(name_example[:flow_id]).to eq('P1A')
        expect(name_example[:yaml_key]).to eq('elisa.provider.onboarding.welcome')
      end
    end

    context 'when there are multiple different inconsistencies' do
      let(:message_entries) do
        [
          # Provider name variants
          ElisaAudit::MessageEntry.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.msg1',
            content: 'Hola %{name}',
            line_number: 10,
            variables: ['name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P2A',
            yaml_key: 'elisa.provider.msg2',
            content: 'Gracias %{provider_name}',
            line_number: 15,
            variables: ['provider_name']
          ),
          # City variants
          ElisaAudit::MessageEntry.new(
            flow_id: 'P3A',
            yaml_key: 'elisa.provider.msg3',
            content: 'En %{ciudad}',
            line_number: 20,
            variables: ['ciudad']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P4A',
            yaml_key: 'elisa.provider.msg4',
            content: 'En %{city}',
            line_number: 25,
            variables: ['city']
          ),
          # Phone variants
          ElisaAudit::MessageEntry.new(
            flow_id: 'P5A',
            yaml_key: 'elisa.provider.msg5',
            content: 'Llama al %{phone}',
            line_number: 30,
            variables: ['phone']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P6A',
            yaml_key: 'elisa.provider.msg6',
            content: 'Teléfono: %{teléfono}',
            line_number: 35,
            variables: ['teléfono']
          )
        ]
      end

      it 'detects all three inconsistencies' do
        result = analyzer.call
        expect(result[:inconsistencies].count).to eq(3)

        concepts = result[:inconsistencies].map { |i| i[:concept] }
        expect(concepts).to include(:provider_name, :city, :phone)
      end

      it 'generates recommendations for each inconsistency' do
        result = analyzer.call
        expect(result[:recommendations].count).to eq(3)
      end

      it 'sets has_issues to true' do
        result = analyzer.call
        expect(result[:has_issues]).to be true
      end
    end

    context 'when messages have no placeholders' do
      let(:message_entries) do
        [
          ElisaAudit::MessageEntry.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.welcome',
            content: 'Hola, bienvenido',
            line_number: 10,
            variables: []
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P2A',
            yaml_key: 'elisa.provider.thanks',
            content: 'Gracias',
            line_number: 15,
            variables: []
          )
        ]
      end

      it 'returns empty results' do
        result = analyzer.call
        expect(result[:all_placeholders]).to be_empty
        expect(result[:inconsistencies]).to be_empty
        expect(result[:has_issues]).to be false
      end
    end

    context 'when only one placeholder is used multiple times' do
      let(:message_entries) do
        [
          ElisaAudit::MessageEntry.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.msg1',
            content: 'Hola %{provider_name}',
            line_number: 10,
            variables: ['provider_name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P2A',
            yaml_key: 'elisa.provider.msg2',
            content: 'Gracias %{provider_name}',
            line_number: 15,
            variables: ['provider_name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P3A',
            yaml_key: 'elisa.provider.msg3',
            content: 'Adiós %{provider_name}',
            line_number: 20,
            variables: ['provider_name']
          )
        ]
      end

      it 'returns no inconsistencies' do
        result = analyzer.call
        expect(result[:inconsistencies]).to be_empty
      end

      it 'tracks the frequency correctly' do
        result = analyzer.call
        expect(result[:all_placeholders]['provider_name']).to eq(3)
      end
    end
  end

  describe '#generate_markdown_report' do
    subject(:analyzer) { described_class.new(message_entries) }

    context 'when there are no inconsistencies' do
      let(:message_entries) do
        [
          ElisaAudit::MessageEntry.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.msg1',
            content: 'Hola %{provider_name}',
            line_number: 10,
            variables: ['provider_name']
          )
        ]
      end

      it 'generates success message' do
        analyzer.call
        report = analyzer.generate_markdown_report

        expect(report).to include('No se encontraron inconsistencias')
        expect(report).to include('✅')
      end
    end

    context 'when there are inconsistencies' do
      let(:message_entries) do
        [
          ElisaAudit::MessageEntry.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.msg1',
            content: 'Hola %{name}',
            line_number: 10,
            variables: ['name']
          ),
          ElisaAudit::MessageEntry.new(
            flow_id: 'P2A',
            yaml_key: 'elisa.provider.msg2',
            content: 'Gracias %{provider_name}',
            line_number: 15,
            variables: ['provider_name']
          )
        ]
      end

      it 'generates report with inconsistencies section' do
        analyzer.call
        report = analyzer.generate_markdown_report

        expect(report).to include('Placeholder Consistency Analysis')
        expect(report).to include('Inconsistencias Detectadas')
        expect(report).to include('⚠️')
      end

      it 'includes all found placeholders table' do
        analyzer.call
        report = analyzer.generate_markdown_report

        expect(report).to include('Placeholders Encontrados')
        expect(report).to include('name')
        expect(report).to include('provider_name')
      end

      it 'includes recommendations section' do
        analyzer.call
        report = analyzer.generate_markdown_report

        expect(report).to include('Recomendaciones de Estandarización')
        expect(report).to include('Estandarizar')
      end

      it 'shows variant examples' do
        analyzer.call
        report = analyzer.generate_markdown_report

        expect(report).to include('elisa.provider.msg1')
        expect(report).to include('elisa.provider.msg2')
      end
    end
  end
end
