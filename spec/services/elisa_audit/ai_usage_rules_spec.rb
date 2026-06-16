# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ElisaAudit::AiUsageRules do
  describe '.expected_for_flow' do
    context 'when flow has documented AI usage' do
      it 'returns correct configuration for P6A bio generation' do
        config = described_class.expected_for_flow('P6A')

        expect(config[:type]).to eq(:generation)
        expect(config[:model]).to eq(:sonnet)
        expect(config[:status]).to eq(:correct)
        expect(config[:generates]).to eq('[BIO]')
      end

      it 'returns correct configuration for P3E city extraction' do
        config = described_class.expected_for_flow('P3E')

        expect(config[:type]).to eq(:extraction)
        expect(config[:model]).to eq(:haiku)
        expect(config[:status]).to eq(:correct)
        expect(config[:extracts]).to eq('ciudad/zonas from free text')
      end

      it 'returns correct configuration for P15 gasto general interpretation' do
        config = described_class.expected_for_flow('P15')

        expect(config[:type]).to eq(:interpretation)
        expect(config[:model]).to eq(:haiku)
        expect(config[:status]).to eq(:verify)
        expect(config[:interprets]).to eq('gasto general detection')
      end
    end

    context 'when flow is fixed template without AI' do
      it 'returns fixed_template for P1A' do
        config = described_class.expected_for_flow('P1A')

        expect(config[:type]).to eq(:fixed_template)
        expect(config[:model]).to be_nil
        expect(config[:status]).to eq(:verify)
      end

      it 'returns fixed_template for P4' do
        config = described_class.expected_for_flow('P4')

        expect(config[:type]).to eq(:fixed_template)
        expect(config[:model]).to be_nil
      end
    end

    context 'when flow requires critical verification' do
      it 'marks P10-P14 as critical_verify' do
        config = described_class.expected_for_flow('P10-P14')

        expect(config[:type]).to eq(:fixed_template)
        expect(config[:status]).to eq(:critical_verify)
        expect(config[:note]).to include('CRÍTICO')
      end
    end

    context 'when flow is undocumented' do
      it 'returns undocumented status for C2A' do
        config = described_class.expected_for_flow('C2A')

        expect(config[:type]).to eq(:undocumented)
        expect(config[:status]).to eq(:undocumented)
        expect(config[:note]).to include('PENDIENTE')
      end

      it 'returns unknown for non-existent flow' do
        config = described_class.expected_for_flow('INVALID_FLOW')

        expect(config[:type]).to eq(:unknown)
        expect(config[:status]).to eq(:undocumented)
        expect(config[:note]).to include('not documented')
      end
    end

    context 'when flow has multiple AI capabilities' do
      it 'returns generation_closing for P16 with interpretation' do
        config = described_class.expected_for_flow('P16')

        expect(config[:type]).to eq(:generation_closing)
        expect(config[:model]).to eq(:haiku)
        expect(config[:generates]).to include('closing message only')
        expect(config[:interprets]).to include('¿Listo para arrancar?')
      end

      it 'returns interpretation_photos for C1A' do
        config = described_class.expected_for_flow('C1A')

        expect(config[:type]).to eq(:interpretation_photos)
        expect(config[:model]).to eq(:haiku)
        expect(config[:interprets]).to include('problem category')
      end
    end
  end

  describe '.proactive?' do
    context 'when flow sends proactive messages' do
      it 'returns true for P10-P14 thank you message' do
        expect(described_class.proactive?('P10-P14')).to be true
      end

      it 'returns true for P16 morning summary' do
        expect(described_class.proactive?('P16')).to be true
      end

      it 'returns true for C4A appointment notice' do
        expect(described_class.proactive?('C4A')).to be true
      end

      it 'returns true for C4D appointment reminders' do
        expect(described_class.proactive?('C4D')).to be true
      end

      it 'returns true for C4E cancellation notice' do
        expect(described_class.proactive?('C4E')).to be true
      end

      it 'returns true for C7A review request' do
        expect(described_class.proactive?('C7A')).to be true
      end

      it 'returns true for C7C review request second attempt' do
        expect(described_class.proactive?('C7C')).to be true
      end
    end

    context 'when flow does not send proactive messages' do
      it 'returns false for P1A onboarding' do
        expect(described_class.proactive?('P1A')).to be false
      end

      it 'returns false for P6A bio generation' do
        expect(described_class.proactive?('P6A')).to be false
      end

      it 'returns false for C3A client search' do
        expect(described_class.proactive?('C3A')).to be false
      end

      it 'returns false for non-existent flow' do
        expect(described_class.proactive?('INVALID_FLOW')).to be false
      end
    end
  end

  describe '.flows_by_type' do
    it 'returns all extraction flows' do
      flows = described_class.flows_by_type(:extraction)

      expect(flows).to include('P3E', 'C2D', 'C3A')
      expect(flows.all? { |f| described_class.expected_for_flow(f)[:type] == :extraction }).to be true
    end

    it 'returns all generation flows' do
      flows = described_class.flows_by_type(:generation)

      expect(flows).to include('P6A', 'P6B')
      expect(flows.all? { |f| described_class.expected_for_flow(f)[:type] == :generation }).to be true
    end

    it 'returns all fixed_template flows' do
      flows = described_class.flows_by_type(:fixed_template)

      expect(flows).to include('P1A', 'P1B', 'P4', 'P5')
      expect(flows.length).to be > 10
    end

    it 'returns empty array for non-existent type' do
      flows = described_class.flows_by_type(:invalid_type)

      expect(flows).to be_empty
    end
  end

  describe '.flows_by_model' do
    it 'returns all flows using Haiku model' do
      flows = described_class.flows_by_model(:haiku)

      expect(flows).to include('P3E', 'P15', 'P16', 'P17', 'C2D')
      expect(flows.all? { |f| described_class.expected_for_flow(f)[:model] == :haiku }).to be true
    end

    it 'returns all flows using Sonnet model' do
      flows = described_class.flows_by_model(:sonnet)

      expect(flows).to include('P6A', 'P6B')
      expect(flows.all? { |f| described_class.expected_for_flow(f)[:model] == :sonnet }).to be true
    end

    it 'returns empty array for non-existent model' do
      flows = described_class.flows_by_model(:gpt4)

      expect(flows).to be_empty
    end
  end

  describe '.flows_by_status' do
    it 'returns all flows marked as correct' do
      flows = described_class.flows_by_status(:correct)

      expect(flows).to include('P3E', 'P6A', 'P6B', 'C2D', 'C3A')
      expect(flows.all? { |f| described_class.expected_for_flow(f)[:status] == :correct }).to be true
    end

    it 'returns all flows requiring verification' do
      flows = described_class.flows_by_status(:verify)

      expect(flows.length).to be > 10
      expect(flows.all? { |f| described_class.expected_for_flow(f)[:status] == :verify }).to be true
    end

    it 'returns flows requiring critical verification' do
      flows = described_class.flows_by_status(:critical_verify)

      expect(flows).to include('P10-P14')
    end

    it 'returns flows needing implementation' do
      flows = described_class.flows_by_status(:implement)

      expect(flows).to include('P7A', 'P7B')
    end
  end

  describe 'FLOWS constant' do
    it 'contains all provider flows P1A-P20' do
      provider_flows = described_class::FLOWS.keys.select { |k| k.start_with?('P') }

      expect(provider_flows.length).to be >= 20
    end

    it 'contains all client flows C1A-C7D' do
      client_flows = described_class::FLOWS.keys.select { |k| k.start_with?('C') }

      expect(client_flows.length).to be >= 20
    end

    it 'all flows have required keys' do
      described_class::FLOWS.each do |flow_id, config|
        expect(config).to have_key(:type)
        expect(config).to have_key(:model)
        expect(config).to have_key(:status)
        expect(config).to have_key(:note)
      end
    end
  end

  describe 'PROACTIVE_TEMPLATES constant' do
    it 'contains exactly 7 proactive flows' do
      expect(described_class::PROACTIVE_TEMPLATES.length).to eq(7)
    end

    it 'all proactive templates are documented in FLOWS' do
      described_class::PROACTIVE_TEMPLATES.each do |flow_id|
        expect(described_class::FLOWS).to have_key(flow_id)
      end
    end
  end
end
