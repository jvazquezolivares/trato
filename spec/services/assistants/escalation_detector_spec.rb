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
      [ "fuga de gas", "olor a quemado", "fuga de agua", "no puedo respirar", "ayuda urgente" ].each do |phrase|
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
      [ "hablar con una persona", "necesito hablar con alguien", "persona real" ].each do |phrase|
        it "detects '#{phrase}' as speak_with_person" do
          result = described_class.call(body: "Quiero #{phrase}", from: from, provider: provider, conversation: conversation)

          expect(result).to eq({ detected: true, reason: "speak_with_person" })
        end
      end
    end

    context "when price negotiation patterns are detected" do
      [ "muy caro", "más barato", "descuento", "no me alcanza" ].each do |phrase|
        it "detects '#{phrase}' as price_negotiation" do
          result = described_class.call(body: "Está #{phrase}", from: from, provider: provider, conversation: conversation)

          expect(result).to eq({ detected: true, reason: "price_negotiation" })
        end
      end
    end

    context "when complaint patterns are detected" do
      [ "mal trabajo", "quedó mal", "no sirve", "reclamo" ].each do |phrase|
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
    before do
      allow(conversation).to receive(:client).and_return(nil)
    end

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

    context "when danger is detected and client exists" do
      let(:client) { instance_double(Client, id: 1, name: "Mariana", phone: from) }

      before do
        allow(conversation).to receive(:client).and_return(client)
        allow(Rails.logger).to receive(:info)
      end

      it "sends emergency alert to client" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: a_string_matching(/🚨 Mariana, esto suena urgente/)
        )
      end

      it "sends emergency alert to provider with client name and keyword" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo en mi casa", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta humo/)
        )
      end

      it "includes client phone in provider emergency alert" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Su número: 📞 #{from}/)
        )
      end

      it "includes contact instruction in provider emergency alert" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Contáctala de inmediato/)
        )
      end

      it "includes provider name in client alert" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: a_string_matching(/llama a Miguel AHORA/)
        )
      end

      it "includes provider phone in client alert" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: a_string_matching(/📞 5212211234567/)
        )
      end

      it "includes 911 instruction in client alert" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: a_string_matching(/Si hay riesgo de incendio: llama al 911/)
        )
      end

      it "sends two messages total (client alert + provider emergency alert)" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).exactly(2).times
      end

      it "sends both emergency messages synchronously within same processing cycle" do
        # Track the order of message sends
        call_order = []
        allow(WhatsAppService).to receive(:send_message) do |args|
          call_order << args[:to]
        end

        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        # Verify both messages were sent in the same method call (not async)
        expect(call_order).to eq([from, provider.phone])
        expect(WhatsAppService).to have_received(:send_message).exactly(2).times
      end

      it "logs the client emergency alert" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/Sent emergency alert to client #{from}/)
        )
      end

      it "logs the provider emergency alert" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/Sent emergency alert to provider #{provider.phone}/)
        )
      end

      it "extracts multi-word danger keywords correctly" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay una fuga de gas", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/reporta fuga de gas/)
        )
      end

      it "uses fallback keyword when no specific match found" do
        # This shouldn't happen in practice, but tests the fallback
        allow_any_instance_of(described_class).to receive(:extract_danger_keyword).and_return("una emergencia")

        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Situación peligrosa", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/reporta una emergencia/)
        )
      end

      context "when client has no name" do
        let(:client) { instance_double(Client, id: 1, name: nil, phone: from) }

        it "uses 'Cliente' as fallback name in client alert" do
          described_class.escalate!(
            conversation: conversation, provider: provider,
            from: from, body: "Hay humo", reason: "danger"
          )

          expect(WhatsAppService).to have_received(:send_message).with(
            to: from,
            message: a_string_matching(/🚨 Cliente, esto suena urgente/)
          )
        end

        it "uses 'Cliente' as fallback name in provider alert" do
          described_class.escalate!(
            conversation: conversation, provider: provider,
            from: from, body: "Hay humo", reason: "danger"
          )

          expect(WhatsAppService).to have_received(:send_message).with(
            to: provider.phone,
            message: a_string_matching(/Tu cliente Cliente reporta/)
          )
        end
      end
    end

    context "when danger is detected but no client exists" do
      before do
        allow(conversation).to receive(:client).and_return(nil)
      end

      it "only sends message to provider" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Hay humo", reason: "danger"
        )

        expect(WhatsAppService).to have_received(:send_message).once
        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/URGENTE/)
        )
      end
    end

    context "when non-danger escalation occurs" do
      let(:client) { instance_double(Client, id: 1, name: "Mariana", phone: from) }

      before do
        allow(conversation).to receive(:client).and_return(client)
      end

      it "does not send emergency alert to client for complaint" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Quedó mal", reason: "complaint"
        )

        expect(WhatsAppService).to have_received(:send_message).once
        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Queja de cliente/)
        )
      end

      it "does not send emergency alert to client for price_negotiation" do
        described_class.escalate!(
          conversation: conversation, provider: provider,
          from: from, body: "Muy caro", reason: "price_negotiation"
        )

        expect(WhatsAppService).to have_received(:send_message).once
      end
    end
  end

  describe "emergency notification integration" do
    let(:client) { instance_double(Client, id: 1, name: "Mariana", phone: from) }

    before do
      allow(conversation).to receive(:client).and_return(client)
      allow(conversation).to receive(:update!).and_return(true)
      allow(WhatsAppService).to receive(:send_message).and_return(true)
      allow(Rails.logger).to receive(:info)
    end

    context "when emergency is detected and escalated in one flow" do
      it "detects danger, escalates, and sends both alerts synchronously" do
        # Step 1: Detect danger
        detection_result = described_class.call(
          body: "Hay humo y chispas en el panel eléctrico",
          from: from,
          provider: provider,
          conversation: conversation
        )

        expect(detection_result).to eq({ detected: true, reason: "danger" })

        # Step 2: Escalate (this would normally be called by the orchestrator)
        described_class.escalate!(
          conversation: conversation,
          provider: provider,
          from: from,
          body: "Hay humo y chispas en el panel eléctrico",
          reason: "danger"
        )

        # Verify conversation was escalated
        expect(conversation).to have_received(:update!).with(stage: "escalated")

        # Verify both emergency messages were sent synchronously
        expect(WhatsAppService).to have_received(:send_message).exactly(2).times

        # Verify client received emergency alert
        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: a_string_matching(/🚨 Mariana, esto suena urgente.*llama a Miguel AHORA.*📞 5212211234567.*Si hay riesgo de incendio: llama al 911/m)
        )

        # Verify provider received emergency alert with detected keyword
        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta (humo|chispas).*Su número: 📞 #{from}.*Contáctala de inmediato/m)
        )

        # Verify logging occurred
        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/Sent emergency alert to client #{from}/)
        )
        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/Sent emergency alert to provider #{provider.phone}/)
        )
      end

      it "sends messages in correct order: client first, then provider" do
        call_order = []
        allow(WhatsAppService).to receive(:send_message) do |args|
          call_order << { to: args[:to], message_type: args[:message].include?("🚨") ? "emergency" : "general" }
        end

        described_class.escalate!(
          conversation: conversation,
          provider: provider,
          from: from,
          body: "Hay una fuga de gas",
          reason: "danger"
        )

        # Verify order: client emergency alert first, then provider emergency alert
        expect(call_order.length).to eq(2)
        expect(call_order[0][:to]).to eq(from)
        expect(call_order[0][:message_type]).to eq("emergency")
        expect(call_order[1][:to]).to eq(provider.phone)
        expect(call_order[1][:message_type]).to eq("emergency")
      end
    end
  end
end
