# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::EscalationDetector do
  let(:provider) { instance_double(Provider, id: 1, name: "Miguel", phone: "5212211234567") }
  let(:conversation) { instance_double(Conversation, id: 1) }
  let(:from) { "5212219876543" }

  before do
    allow(WhatsAppService).to receive(:send_message).and_return(true)
    allow(conversation).to receive(:update!).and_return(true)
  end

  describe ".call" do
    context "when body is blank" do
      it "returns no escalation" do
        result = described_class.call(body: "", from: from, provider: provider, conversation: conversation)

        expect(result).to eq({ detected: false, reason: nil })
      end
    end

    context "when single-word danger keywords are detected" do
      %w[humo quemado chispas cortocircuito incendio fuego derrumbe
         emergencia peligro auxilio ambulancia bomberos accidente].each do |keyword|
        it "detects '#{keyword}' as danger" do
          result = described_class.call(body: "Hay #{keyword} en mi casa", from: from, provider: provider, conversation: conversation)

          expect(result).to eq({ detected: true, reason: "danger" })
        end
      end
    end

    context "when multi-word danger phrases are detected" do
      ["fuga de gas", "olor a quemado", "fuga de agua", "no puedo respirar", "ayuda urgente"].each do |phrase|
        it "detects '#{phrase}' as danger" do
          result = described_class.call(body: "Oye, hay #{phrase}", from: from, provider: provider, conversation: conversation)

          expect(result).to eq({ detected: true, reason: "danger" })
        end
      end
    end

    context "when short keywords appear inside unrelated words" do
      it "does not detect 'gas' inside 'gastos'" do
        result = described_class.call(body: "Tengo muchos gastos", from: from, provider: provider, conversation: conversation)

        expect(result).to eq({ detected: false, reason: nil })
      end
    end

    context "when speak-with-person patterns are detected" do
      ["hablar con una persona", "necesito hablar con alguien", "persona real"].each do |phrase|
        it "detects '#{phrase}' as speak_with_person" do
          result = described_class.call(body: "Quiero #{phrase}", from: from, provider: provider, conversation: conversation)

          expect(result).to eq({ detected: true, reason: "speak_with_person" })
        end
      end
    end

    context "when price negotiation patterns are detected" do
      ["muy caro", "más barato", "descuento", "no me alcanza"].each do |phrase|
        it "detects '#{phrase}' as price_negotiation" do
          result = described_class.call(body: "Está #{phrase}", from: from, provider: provider, conversation: conversation)

          expect(result).to eq({ detected: true, reason: "price_negotiation" })
        end
      end
    end

    context "when complaint patterns are detected" do
      ["mal trabajo", "quedó mal", "no sirve", "reclamo"].each do |phrase|
        it "detects '#{phrase}' as complaint" do
          result = described_class.call(body: "Fue un #{phrase}", from: from, provider: provider, conversation: conversation)

          expect(result).to eq({ detected: true, reason: "complaint" })
        end
      end
    end

    context "when no escalation triggers are present" do
      it "returns no escalation for normal messages" do
        result = described_class.call(body: "Necesito revisar mi instalación", from: from, provider: provider, conversation: conversation)

        expect(result).to eq({ detected: false, reason: nil })
      end
    end
  end

  describe ".escalate!" do
    it "updates conversation stage to escalated" do
      described_class.escalate!(
        conversation: conversation, provider: provider,
        from: from, body: "Hay humo", reason: "danger"
      )

      expect(conversation).to have_received(:update!).with(stage: "escalated")
    end

    it "sends escalation message to provider" do
      described_class.escalate!(
        conversation: conversation, provider: provider,
        from: from, body: "Hay humo", reason: "danger"
      )

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: a_string_matching(/URGENTE.*emergencia/m)
      )
    end

    it "includes client phone in escalation message" do
      described_class.escalate!(
        conversation: conversation, provider: provider,
        from: from, body: "Hay humo", reason: "danger"
      )

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: a_string_matching(/5212219876543/)
      )
    end

    it "builds complaint message for complaint reason" do
      described_class.escalate!(
        conversation: conversation, provider: provider,
        from: from, body: "Quedó mal", reason: "complaint"
      )

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: a_string_matching(/Queja de cliente/)
      )
    end

    it "builds angry client message" do
      described_class.escalate!(
        conversation: conversation, provider: provider,
        from: from, body: "Estoy furioso", reason: "angry_client"
      )

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: a_string_matching(/Cliente molesto/)
      )
    end
  end
end
