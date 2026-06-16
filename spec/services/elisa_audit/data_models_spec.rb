# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../app/services/elisa_audit/data_models'

RSpec.describe ElisaAudit do
  describe ElisaAudit::MessageEntry do
    describe '#has_variables?' do
      context 'when message has interpolation variables' do
        it 'returns true' do
          entry = described_class.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.onboarding.greeting',
            content: 'Hola %{name}',
            line_number: 42,
            variables: ['name']
          )

          expect(entry.has_variables?).to be true
        end

        it 'returns true with multiple variables' do
          entry = described_class.new(
            flow_id: 'C1A',
            yaml_key: 'elisa.client.greeting',
            content: 'Hola, soy asistente de %{provider_name} en %{ciudad}',
            line_number: 100,
            variables: %w[provider_name ciudad]
          )

          expect(entry.has_variables?).to be true
        end
      end

      context 'when message has no variables' do
        it 'returns false with empty array' do
          entry = described_class.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.onboarding.welcome',
            content: '¡Hola! 👋 Soy Elisa',
            line_number: 40,
            variables: []
          )

          expect(entry.has_variables?).to be false
        end

        it 'returns false with nil variables' do
          entry = described_class.new(
            flow_id: 'P1A',
            yaml_key: 'elisa.provider.onboarding.welcome',
            content: '¡Hola! 👋 Soy Elisa',
            line_number: 40,
            variables: nil
          )

          expect(entry.has_variables?).to be false
        end
      end
    end

    describe '#formatted_variables' do
      it 'returns dash when no variables' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'elisa.provider.onboarding.welcome',
          content: '¡Hola!',
          line_number: 40,
          variables: []
        )

        expect(entry.formatted_variables).to eq('-')
      end

      it 'formats single variable with %{} syntax' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'elisa.provider.onboarding.greeting',
          content: 'Hola %{name}',
          line_number: 42,
          variables: ['name']
        )

        expect(entry.formatted_variables).to eq('%{name}')
      end

      it 'formats multiple variables separated by commas' do
        entry = described_class.new(
          flow_id: 'C1A',
          yaml_key: 'elisa.client.greeting',
          content: 'Hola, soy asistente de %{provider_name} en %{ciudad}',
          line_number: 100,
          variables: %w[provider_name ciudad]
        )

        expect(entry.formatted_variables).to eq('%{provider_name}, %{ciudad}')
      end
    end
  end

  describe ElisaAudit::AiUsageViolation do
    describe '#severity_label' do
      it 'returns critical badge for critical severity' do
        violation = described_class.new(
          type: :improper_generation,
          flow_id: 'P10-P14',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'Uses AI',
          expected_impl: 'Should be fixed',
          severity: :critical,
          model_used: :haiku
        )

        expect(violation.severity_label).to eq('🔴 CRÍTICO')
      end

      it 'returns moderate badge for moderate severity' do
        violation = described_class.new(
          type: :missing_extraction,
          flow_id: 'P15',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'No AI',
          expected_impl: 'Should use AI',
          severity: :moderate,
          model_used: nil
        )

        expect(violation.severity_label).to eq('🟡 MODERADO')
      end

      it 'returns minor badge for minor severity' do
        violation = described_class.new(
          type: :wrong_model,
          flow_id: 'P6A',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'Uses Haiku',
          expected_impl: 'Should use Sonnet',
          severity: :minor,
          model_used: :haiku
        )

        expect(violation.severity_label).to eq('🟢 MENOR')
      end
    end

    describe '#type_label' do
      it 'returns Spanish label for improper_generation' do
        violation = described_class.new(
          type: :improper_generation,
          flow_id: 'P10-P14',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'test',
          expected_impl: 'test',
          severity: :critical,
          model_used: :haiku
        )

        expect(violation.type_label).to eq('Generación impropia')
      end

      it 'returns Spanish label for missing_extraction' do
        violation = described_class.new(
          type: :missing_extraction,
          flow_id: 'P15',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'test',
          expected_impl: 'test',
          severity: :moderate,
          model_used: nil
        )

        expect(violation.type_label).to eq('Extracción faltante')
      end

      it 'returns Spanish label for missing_interpretation' do
        violation = described_class.new(
          type: :missing_interpretation,
          flow_id: 'P17',
          file_path: 'app/services/test.rb',
          line_number: 42,
          method_name: 'test_method',
          current_impl: 'test',
          expected_impl: 'test',
          severity: :moderate,
          model_used: nil
        )

        expect(violation.type_label).to eq('Interpretación faltante')
      end
    end
  end

  describe ElisaAudit::TemplateRequirement do
    describe '#formatted_variables' do
      it 'returns "Ninguna" when no variables' do
        template = described_class.new(
          flow_id: 'P16',
          template_name: 'morning_summary',
          category: 'UTILITY',
          message_text: 'Buenos días',
          variables: [],
          is_proactive: true,
          yaml_key: 'elisa.provider.summary.morning'
        )

        expect(template.formatted_variables).to eq('Ninguna')
      end

      it 'returns "Ninguna" when variables is nil' do
        template = described_class.new(
          flow_id: 'P16',
          template_name: 'morning_summary',
          category: 'UTILITY',
          message_text: 'Buenos días',
          variables: nil,
          is_proactive: true,
          yaml_key: 'elisa.provider.summary.morning'
        )

        expect(template.formatted_variables).to eq('Ninguna')
      end

      it 'formats single variable with type and example' do
        template = described_class.new(
          flow_id: 'P10-P14',
          template_name: 'thank_you',
          category: 'UTILITY',
          message_text: 'Gracias {{name}}',
          variables: [{ name: 'name', type: 'text', example: 'Miguel' }],
          is_proactive: true,
          yaml_key: 'elisa.provider.thank_you'
        )

        expect(template.formatted_variables).to include("name (text): ejemplo = 'Miguel'")
      end

      it 'formats multiple variables with newlines' do
        template = described_class.new(
          flow_id: 'C4A',
          template_name: 'appointment_notice',
          category: 'UTILITY',
          message_text: 'Cita con {{cliente}} en {{zona}}',
          variables: [
            { name: 'cliente', type: 'text', example: 'Mariana' },
            { name: 'zona', type: 'text', example: 'Centro' }
          ],
          is_proactive: true,
          yaml_key: 'elisa.client.appointment.notice'
        )

        result = template.formatted_variables
        expect(result).to include("cliente (text): ejemplo = 'Mariana'")
        expect(result).to include("zona (text): ejemplo = 'Centro'")
      end
    end

    describe '#category_badge' do
      it 'returns UTILITY badge' do
        template = described_class.new(
          flow_id: 'P16',
          template_name: 'morning_summary',
          category: 'UTILITY',
          message_text: 'Buenos días',
          variables: [],
          is_proactive: true,
          yaml_key: 'elisa.provider.summary.morning'
        )

        expect(template.category_badge).to eq('🔧 UTILITY')
      end

      it 'returns MARKETING badge' do
        template = described_class.new(
          flow_id: 'C7A',
          template_name: 'review_request',
          category: 'MARKETING',
          message_text: 'Déjanos tu reseña',
          variables: [],
          is_proactive: true,
          yaml_key: 'elisa.client.review.request'
        )

        expect(template.category_badge).to eq('📢 MARKETING')
      end
    end
  end

  describe ElisaAudit::ComparisonEntry do
    describe '#status_badge' do
      it 'returns exact match badge' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'elisa.provider.onboarding.welcome',
          current_text: '¡Hola!',
          pdf_text: '¡Hola!',
          status: :exact_match,
          notes: nil
        )

        expect(entry.status_badge).to eq('✅ Coincide')
      end

      it 'returns mismatch badge' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'elisa.provider.onboarding.welcome',
          current_text: '¡Hola!',
          pdf_text: 'Hola',
          status: :mismatch,
          notes: 'Missing emoji'
        )

        expect(entry.status_badge).to eq('❌ Discrepancia')
      end

      it 'returns missing badge' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: nil,
          current_text: nil,
          pdf_text: 'Missing message',
          status: :missing,
          notes: nil
        )

        expect(entry.status_badge).to eq('⚠️ Falta en YAML')
      end

      it 'returns extra badge' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'elisa.provider.extra',
          current_text: 'Extra message',
          pdf_text: nil,
          status: :extra,
          notes: nil
        )

        expect(entry.status_badge).to eq('⚠️ Extra en YAML')
      end

      it 'returns pending badge when status is nil' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'elisa.provider.onboarding.welcome',
          current_text: '¡Hola!',
          pdf_text: nil,
          status: nil,
          notes: nil
        )

        expect(entry.status_badge).to eq('⏳ Pendiente')
      end
    end

    describe '#requires_attention?' do
      it 'returns true for mismatch status' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'test',
          current_text: 'text1',
          pdf_text: 'text2',
          status: :mismatch,
          notes: nil
        )

        expect(entry.requires_attention?).to be true
      end

      it 'returns true for missing status' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: nil,
          current_text: nil,
          pdf_text: 'text',
          status: :missing,
          notes: nil
        )

        expect(entry.requires_attention?).to be true
      end

      it 'returns true for extra status' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'test',
          current_text: 'text',
          pdf_text: nil,
          status: :extra,
          notes: nil
        )

        expect(entry.requires_attention?).to be true
      end

      it 'returns false for exact_match status' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'test',
          current_text: 'text',
          pdf_text: 'text',
          status: :exact_match,
          notes: nil
        )

        expect(entry.requires_attention?).to be false
      end

      it 'returns false for nil status' do
        entry = described_class.new(
          flow_id: 'P1A',
          yaml_key: 'test',
          current_text: 'text',
          pdf_text: nil,
          status: nil,
          notes: nil
        )

        expect(entry.requires_attention?).to be false
      end
    end
  end
end
