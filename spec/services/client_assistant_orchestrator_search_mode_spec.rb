# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientAssistantOrchestrator, type: :service do
  describe ".call_search_mode" do
    let(:from) { "5212291234567" } # Veracruz prefix (229)
    let(:body) { "Hola, necesito un plomero" }

    before do
      # Stub Redis
      allow(REDIS).to receive(:setex)

      # Stub WhatsAppService
      allow(WhatsAppService).to receive(:send_message_with_buttons)
      allow(WhatsAppService).to receive(:send_message)
    end

    context "when phone prefix matches a known state" do
      before do
        # Mock ZonesService to return Veracruz for prefix 229
        allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("Veracruz")
      end

      it "detects the state from phone prefix" do
        described_class.call_search_mode(from: from, body: body)

        expect(ZonesService).to have_received(:detect_state_from_prefix).with(from)
      end

      it "sends greeting message with detected region" do
        described_class.call_search_mode(from: from, body: body)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de Veracruz. ¿Buscas un técnico en esta región?",
          buttons: [
            { id: "region_yes_Veracruz", title: "Sí, en Veracruz" },
            { id: "region_no", title: "No, en otro lugar" }
          ]
        )
      end

      it "stores detected region in Redis context" do
        described_class.call_search_mode(from: from, body: body)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          { detected_state: "Veracruz", stage: "region_confirmation" }.to_json
        )
      end
    end

    context "when phone prefix matches Puebla state" do
      let(:from) { "5212221234567" } # Puebla prefix (222)

      before do
        allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("Puebla")
      end

      it "sends greeting with Puebla region" do
        described_class.call_search_mode(from: from, body: body)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de Puebla. ¿Buscas un técnico en esta región?",
          buttons: [
            { id: "region_yes_Puebla", title: "Sí, en Puebla" },
            { id: "region_no", title: "No, en otro lugar" }
          ]
        )
      end
    end

    context "when phone prefix matches Hidalgo state" do
      let(:from) { "5217711234567" } # Hidalgo prefix (771)

      before do
        allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("Hidalgo")
      end

      it "sends greeting with Hidalgo region" do
        described_class.call_search_mode(from: from, body: body)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de Hidalgo. ¿Buscas un técnico en esta región?",
          buttons: [
            { id: "region_yes_Hidalgo", title: "Sí, en Hidalgo" },
            { id: "region_no", title: "No, en otro lugar" }
          ]
        )
      end
    end

    context "when phone prefix matches Oaxaca state" do
      let(:from) { "5219511234567" } # Oaxaca prefix (951)

      before do
        allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("Oaxaca")
      end

      it "sends greeting with Oaxaca region" do
        described_class.call_search_mode(from: from, body: body)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de Oaxaca. ¿Buscas un técnico en esta región?",
          buttons: [
            { id: "region_yes_Oaxaca", title: "Sí, en Oaxaca" },
            { id: "region_no", title: "No, en otro lugar" }
          ]
        )
      end
    end

    context "when phone prefix does not match any known state" do
      let(:from) { "5215512345678" } # Mexico City prefix (55) - not in zones.json

      before do
        allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return(nil)
        allow(Assistants::ProviderSearchService).to receive(:call)
      end

      it "falls back to existing search mode" do
        described_class.call_search_mode(from: from, body: body)

        expect(Assistants::ProviderSearchService).to have_received(:call).with(
          from: from,
          body: body
        )
      end

      it "does not send region confirmation message" do
        described_class.call_search_mode(from: from, body: body)

        expect(WhatsAppService).not_to have_received(:send_message_with_buttons)
      end

      it "does not store region in Redis" do
        described_class.call_search_mode(from: from, body: body)

        expect(REDIS).not_to have_received(:setex)
      end
    end

    context "when ZonesService returns blank state" do
      before do
        allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("")
        allow(Assistants::ProviderSearchService).to receive(:call)
      end

      it "falls back to existing search mode" do
        described_class.call_search_mode(from: from, body: body)

        expect(Assistants::ProviderSearchService).to have_received(:call).with(
          from: from,
          body: body
        )
      end
    end
  end

  describe "#process_search_mode" do
    let(:from) { "5212291234567" }
    let(:body) { "Hola" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(REDIS).to receive(:setex)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
      allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("Veracruz")
    end

    it "calls ZonesService to detect state" do
      orchestrator.process_search_mode

      expect(ZonesService).to have_received(:detect_state_from_prefix).with(from)
    end

    it "handles region detection when state is found" do
      orchestrator.process_search_mode

      expect(WhatsAppService).to have_received(:send_message_with_buttons)
    end
  end

  describe "#handle_region_detected" do
    let(:from) { "5212291234567" }
    let(:body) { "Hola" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:detected_state) { "Veracruz" }

    before do
      allow(REDIS).to receive(:setex)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
    end

    it "sends message with correct greeting format" do
      orchestrator.send(:handle_region_detected, detected_state)

      expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
        to: from,
        message: "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de Veracruz. ¿Buscas un técnico en esta región?",
        buttons: array_including(
          { id: "region_yes_Veracruz", title: "Sí, en Veracruz" },
          { id: "region_no", title: "No, en otro lugar" }
        )
      )
    end

    it "stores context with detected state and stage" do
      orchestrator.send(:handle_region_detected, detected_state)

      expect(REDIS).to have_received(:setex).with(
        "client_search:#{from}",
        86_400,
        { detected_state: "Veracruz", stage: "region_confirmation" }.to_json
      )
    end
  end

  describe "#store_search_context" do
    let(:from) { "5212291234567" }
    let(:body) { "Hola" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(REDIS).to receive(:setex)
    end

    it "stores context in Redis with 24-hour TTL" do
      orchestrator.send(:store_search_context, detected_state: "Veracruz", stage: "region_confirmation")

      expect(REDIS).to have_received(:setex).with(
        "client_search:#{from}",
        86_400,
        { detected_state: "Veracruz", stage: "region_confirmation" }.to_json
      )
    end

    it "accepts multiple context parameters" do
      orchestrator.send(:store_search_context, detected_state: "Puebla", stage: "zone_selection", selected_zone: "Centro")

      expect(REDIS).to have_received(:setex).with(
        "client_search:#{from}",
        86_400,
        { detected_state: "Puebla", stage: "zone_selection", selected_zone: "Centro" }.to_json
      )
    end
  end

  describe "#get_search_context" do
    let(:from) { "5212291234567" }
    let(:body) { "Hola" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(REDIS).to receive(:get)
    end

    context "when context exists in Redis" do
      let(:stored_context) { { detected_state: "Veracruz", stage: "region_confirmation" } }

      before do
        allow(REDIS).to receive(:get).with("client_search:#{from}").and_return(stored_context.to_json)
      end

      it "retrieves and parses the context" do
        result = orchestrator.send(:get_search_context)

        expect(result).to eq(stored_context)
      end

      it "symbolizes keys" do
        result = orchestrator.send(:get_search_context)

        expect(result.keys).to all(be_a(Symbol))
      end
    end

    context "when context does not exist in Redis" do
      before do
        allow(REDIS).to receive(:get).with("client_search:#{from}").and_return(nil)
      end

      it "returns nil" do
        result = orchestrator.send(:get_search_context)

        expect(result).to be_nil
      end
    end

    context "when context is blank string" do
      before do
        allow(REDIS).to receive(:get).with("client_search:#{from}").and_return("")
      end

      it "returns nil" do
        result = orchestrator.send(:get_search_context)

        expect(result).to be_nil
      end
    end

    context "when JSON parsing fails" do
      before do
        allow(REDIS).to receive(:get).with("client_search:#{from}").and_return("invalid json")
        allow(Rails.logger).to receive(:error)
      end

      it "returns nil" do
        result = orchestrator.send(:get_search_context)

        expect(result).to be_nil
      end

      it "logs the error" do
        orchestrator.send(:get_search_context)

        expect(Rails.logger).to have_received(:error).with(
          /\[ClientAssistantOrchestrator\] Failed to parse search context:/
        )
      end
    end
  end
end
