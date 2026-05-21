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

  describe "#handle_region_confirmation_response" do
    let(:from) { "5212291234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:search_context) { { detected_state: "Veracruz", stage: "region_confirmation" } }

    before do
      allow(REDIS).to receive(:setex)
      allow(WhatsAppService).to receive(:send_list_message)
      allow(WhatsAppService).to receive(:send_message)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
    end

    context "when user confirms with button ID" do
      let(:body) { "region_yes_Veracruz" }
      let(:zones) { ["Centro Histórico", "Boca del Río", "Costa Verde"] }

      before do
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return(zones)
      end

      it "retrieves zones for the detected state" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(ZonesService).to have_received(:zones_for_state).with("Veracruz")
      end

      it "sends List Message with zones for that state" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "Zonas en Veracruz")
          )
        )
      end

      it "updates context to zone_selection stage" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            stage: "zone_selection",
            region_scope: "state"
          }.to_json
        )
      end
    end

    context "when user confirms with natural language (Sí)" do
      let(:body) { "Sí" }
      let(:zones) { ["Centro Histórico", "Boca del Río"] }

      before do
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return(zones)
      end

      it "sends zones for detected state" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end
    end

    context "when user confirms with natural language (Si - without accent)" do
      let(:body) { "Si" }
      let(:zones) { ["Centro Histórico", "Boca del Río"] }

      before do
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return(zones)
      end

      it "sends zones for detected state" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end
    end

    context "when user confirms with natural language (Claro)" do
      let(:body) { "Claro" }
      let(:zones) { ["Centro Histórico", "Boca del Río"] }

      before do
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return(zones)
      end

      it "sends zones for detected state" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end
    end

    context "when user confirms with state name in message" do
      let(:body) { "Sí, en Veracruz" }
      let(:zones) { ["Centro Histórico", "Boca del Río"] }

      before do
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return(zones)
      end

      it "sends zones for detected state" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end
    end

    context "when zones are empty for state" do
      let(:body) { "Sí" }

      before do
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return([])
        allow(Rails.logger).to receive(:error)
      end

      it "logs error" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(Rails.logger).to have_received(:error).with(
          /\[ClientAssistantOrchestrator\] No zones found for state: Veracruz/
        )
      end

      it "sends error message to user" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: /Lo siento, no tengo zonas configuradas para Veracruz/
        )
      end

      it "does not send list message" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).not_to have_received(:send_list_message)
      end
    end

    context "when user declines with button ID" do
      let(:body) { "region_no" }
      let(:all_zones) { ["Centro Histórico", "Boca del Río", "Cholula", "Pachuca Centro"] }

      before do
        allow(ZonesService).to receive(:all_zones).and_return(all_zones)
      end

      it "retrieves all zones from all states" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(ZonesService).to have_received(:all_zones)
      end

      it "sends List Message with all zones" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "Todas las zonas")
          )
        )
      end

      it "updates context to zone_selection stage with all scope" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            stage: "zone_selection",
            region_scope: "all"
          }.to_json
        )
      end
    end

    context "when user declines with natural language (No)" do
      let(:body) { "No" }
      let(:all_zones) { ["Centro Histórico", "Cholula"] }

      before do
        allow(ZonesService).to receive(:all_zones).and_return(all_zones)
      end

      it "sends all zones" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end
    end

    context "when user declines with natural language (otro lugar)" do
      let(:body) { "En otro lugar" }
      let(:all_zones) { ["Centro Histórico", "Cholula"] }

      before do
        allow(ZonesService).to receive(:all_zones).and_return(all_zones)
      end

      it "sends all zones" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end
    end

    context "when all zones are empty" do
      let(:body) { "No" }

      before do
        allow(ZonesService).to receive(:all_zones).and_return([])
        allow(Rails.logger).to receive(:error)
      end

      it "logs error" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(Rails.logger).to have_received(:error).with(
          /\[ClientAssistantOrchestrator\] No zones found in zones.json/
        )
      end

      it "sends error message to user" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: /Lo siento, tengo un problema técnico/
        )
      end
    end

    context "when user response is unclear" do
      let(:body) { "Tal vez" }

      it "sends clarification message" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No entendí tu respuesta. ¿Buscas un técnico en Veracruz?"
        )
      end

      it "resends buttons" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "Por favor selecciona una opción:",
          buttons: [
            { id: "region_yes_Veracruz", title: "Sí, en Veracruz" },
            { id: "region_no", title: "No, en otro lugar" }
          ]
        )
      end

      it "does not send list message" do
        orchestrator.send(:handle_region_confirmation_response, search_context)

        expect(WhatsAppService).not_to have_received(:send_list_message)
      end
    end
  end

  describe "#region_confirmed?" do
    let(:from) { "5212291234567" }
    let(:body) { "Sí" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    it "returns true for button ID" do
      result = orchestrator.send(:region_confirmed?, "region_yes_Veracruz", "Veracruz")
      expect(result).to be true
    end

    it "returns true for 'Sí'" do
      result = orchestrator.send(:region_confirmed?, "Sí", "Veracruz")
      expect(result).to be true
    end

    it "returns true for 'Si' (without accent)" do
      result = orchestrator.send(:region_confirmed?, "Si", "Veracruz")
      expect(result).to be true
    end

    it "returns true for 'yes'" do
      result = orchestrator.send(:region_confirmed?, "yes", "Veracruz")
      expect(result).to be true
    end

    it "returns true for 'claro'" do
      result = orchestrator.send(:region_confirmed?, "claro", "Veracruz")
      expect(result).to be true
    end

    it "returns true for 'dale'" do
      result = orchestrator.send(:region_confirmed?, "dale", "Veracruz")
      expect(result).to be true
    end

    it "returns true for 'en Veracruz'" do
      result = orchestrator.send(:region_confirmed?, "en Veracruz", "Veracruz")
      expect(result).to be true
    end

    it "returns false for 'no'" do
      result = orchestrator.send(:region_confirmed?, "no", "Veracruz")
      expect(result).to be false
    end

    it "returns false for blank body" do
      result = orchestrator.send(:region_confirmed?, "", "Veracruz")
      expect(result).to be false
    end

    it "returns false for nil body" do
      result = orchestrator.send(:region_confirmed?, nil, "Veracruz")
      expect(result).to be false
    end
  end

  describe "#region_declined?" do
    let(:from) { "5212291234567" }
    let(:body) { "No" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    it "returns true for button ID" do
      result = orchestrator.send(:region_declined?, "region_no")
      expect(result).to be true
    end

    it "returns true for 'no'" do
      result = orchestrator.send(:region_declined?, "no")
      expect(result).to be true
    end

    it "returns true for 'nop'" do
      result = orchestrator.send(:region_declined?, "nop")
      expect(result).to be true
    end

    it "returns true for 'otro lugar'" do
      result = orchestrator.send(:region_declined?, "otro lugar")
      expect(result).to be true
    end

    it "returns true for 'otra región'" do
      result = orchestrator.send(:region_declined?, "otra región")
      expect(result).to be true
    end

    it "returns true for 'en otro lugar'" do
      result = orchestrator.send(:region_declined?, "en otro lugar")
      expect(result).to be true
    end

    it "returns false for 'sí'" do
      result = orchestrator.send(:region_declined?, "sí")
      expect(result).to be false
    end

    it "returns false for blank body" do
      result = orchestrator.send(:region_declined?, "")
      expect(result).to be false
    end

    it "returns false for nil body" do
      result = orchestrator.send(:region_declined?, nil)
      expect(result).to be false
    end
  end

  describe "#handle_zone_selection_response" do
    let(:from) { "5212291234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(REDIS).to receive(:setex)
      allow(WhatsAppService).to receive(:send_message)
      allow(Rails.logger).to receive(:info)
    end

    context "when user selects a zone from state-specific list" do
      let(:body) { "Centro Histórico" }
      let(:search_context) do
        {
          detected_state: "Veracruz",
          stage: "zone_selection",
          region_scope: "state"
        }
      end

      before do
        allow(WhatsAppService).to receive(:send_list_message)
      end

      it "stores the selected zone in context" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            stage: "category_selection",
            category_page: 1
          }.to_json
        )
      end

      it "sends categories List Message" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "¿Qué tipo de técnico?")
          )
        )
      end

      it "logs the zone selection" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Zone selected: Centro Histórico for client #{from}. Sent categories page 1."
        )
      end

      it "updates stage to category_selection" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            stage: "category_selection",
            category_page: 1
          }.to_json
        )
      end
    end

    context "when user selects a zone from all zones list" do
      let(:body) { "Cholula" }
      let(:search_context) do
        {
          detected_state: "Veracruz",
          stage: "zone_selection",
          region_scope: "all"
        }
      end

      before do
        allow(WhatsAppService).to receive(:send_list_message)
      end

      it "stores the selected zone with all scope" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "all",
            selected_zone: "Cholula",
            stage: "category_selection",
            category_page: 1
          }.to_json
        )
      end

      it "sends categories List Message" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "¿Qué tipo de técnico?")
          )
        )
      end
    end

    context "when user selects a zone with special characters" do
      let(:body) { "Boca del Río" }
      let(:search_context) do
        {
          detected_state: "Veracruz",
          stage: "zone_selection",
          region_scope: "state"
        }
      end

      before do
        allow(WhatsAppService).to receive(:send_list_message)
      end

      it "stores the zone name correctly" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Boca del Río",
            stage: "category_selection",
            category_page: 1
          }.to_json
        )
      end
    end

    context "when zone selection is blank" do
      let(:body) { "" }
      let(:search_context) do
        {
          detected_state: "Veracruz",
          stage: "zone_selection",
          region_scope: "state"
        }
      end

      it "sends error message" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No pude identificar la zona. ¿Puedes seleccionar una opción de la lista?"
        )
      end

      it "does not store context" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).not_to have_received(:setex)
      end

      it "does not log zone selection" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(Rails.logger).not_to have_received(:info)
      end
    end

    context "when zone selection is only whitespace" do
      let(:body) { "   " }
      let(:search_context) do
        {
          detected_state: "Veracruz",
          stage: "zone_selection",
          region_scope: "state"
        }
      end

      it "sends error message" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No pude identificar la zona. ¿Puedes seleccionar una opción de la lista?"
        )
      end

      it "does not store context" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).not_to have_received(:setex)
      end
    end

    context "when preserving detected_state from previous context" do
      let(:body) { "Pachuca Centro" }
      let(:search_context) do
        {
          detected_state: "Hidalgo",
          stage: "zone_selection",
          region_scope: "state"
        }
      end

      before do
        allow(WhatsAppService).to receive(:send_list_message)
      end

      it "preserves the detected_state in new context" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Hidalgo",
            region_scope: "state",
            selected_zone: "Pachuca Centro",
            stage: "category_selection",
            category_page: 1
          }.to_json
        )
      end
    end

    context "when preserving region_scope from previous context" do
      let(:body) { "Oaxaca Centro" }
      let(:search_context) do
        {
          detected_state: "Oaxaca",
          stage: "zone_selection",
          region_scope: "all"
        }
      end

      before do
        allow(WhatsAppService).to receive(:send_list_message)
      end

      it "preserves the region_scope in new context" do
        orchestrator.send(:handle_zone_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Oaxaca",
            region_scope: "all",
            selected_zone: "Oaxaca Centro",
            stage: "category_selection",
            category_page: 1
          }.to_json
        )
      end
    end
  end

  describe "#handle_search_flow_response with zone_selection stage" do
    let(:from) { "5212291234567" }
    let(:body) { "Centro Histórico" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(REDIS).to receive(:setex)
      allow(WhatsAppService).to receive(:send_message)
      allow(Rails.logger).to receive(:info)
    end

    context "when stage is zone_selection" do
      let(:search_context) do
        {
          detected_state: "Veracruz",
          stage: "zone_selection",
          region_scope: "state"
        }
      end

      it "calls handle_zone_selection_response" do
        allow(orchestrator).to receive(:handle_zone_selection_response)

        orchestrator.send(:handle_search_flow_response, search_context)

        expect(orchestrator).to have_received(:handle_zone_selection_response).with(search_context)
      end
    end

    context "when stage is unknown" do
      let(:search_context) do
        {
          detected_state: "Veracruz",
          stage: "unknown_stage"
        }
      end

      before do
        allow(Rails.logger).to receive(:warn)
        allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("Veracruz")
        allow(WhatsAppService).to receive(:send_message_with_buttons)
      end

      it "logs warning" do
        orchestrator.send(:handle_search_flow_response, search_context)

        expect(Rails.logger).to have_received(:warn).with(
          "[ClientAssistantOrchestrator] Unknown search stage: unknown_stage"
        )
      end

      it "falls back to new search" do
        orchestrator.send(:handle_search_flow_response, search_context)

        expect(ZonesService).to have_received(:detect_state_from_prefix).with(from)
      end
    end
  end

  # Integration tests for full "Sí" and "No" paths
  describe "Integration: Full region confirmation flow" do
    let(:from) { "5212291234567" } # Veracruz prefix
    let(:veracruz_zones) { ["Centro Histórico", "Boca del Río", "Costa Verde"] }
    let(:all_zones) { ["Centro Histórico", "Boca del Río", "Cholula", "Pachuca Centro", "Oaxaca Centro"] }

    before do
      allow(REDIS).to receive(:setex)
      allow(REDIS).to receive(:get)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
      allow(WhatsAppService).to receive(:send_list_message)
      allow(WhatsAppService).to receive(:send_message)
      allow(ZonesService).to receive(:detect_state_from_prefix).with(from).and_return("Veracruz")
    end

    context "when user confirms 'Sí' path (state-specific zones)" do
      it "shows only zones for detected state" do
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return(veracruz_zones)
        allow(ZonesService).to receive(:all_zones).and_return(all_zones)

        # Step 1: Initial detection
        described_class.call_search_mode(from: from, body: "Hola")

        # Verify region confirmation message sent
        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de Veracruz. ¿Buscas un técnico en esta región?",
          buttons: [
            { id: "region_yes_Veracruz", title: "Sí, en Veracruz" },
            { id: "region_no", title: "No, en otro lugar" }
          ]
        )

        # Step 2: User confirms with "Sí"
        orchestrator = described_class.new_search_mode(from: from, body: "Sí")
        search_context = { detected_state: "Veracruz", stage: "region_confirmation" }

        orchestrator.send(:handle_region_confirmation_response, search_context)

        # Verify zones_for_state called (not all_zones)
        expect(ZonesService).to have_received(:zones_for_state).with("Veracruz")
        expect(ZonesService).not_to have_received(:all_zones)

        # Verify List Message sent with state-specific zones
        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "Zonas en Veracruz")
          )
        )

        # Verify context stored with region_scope: "state"
        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            stage: "zone_selection",
            region_scope: "state"
          }.to_json
        )
      end
    end

    context "when user declines 'No' path (all zones)" do
      it "shows all zones across all states" do
        allow(ZonesService).to receive(:all_zones).and_return(all_zones)
        allow(ZonesService).to receive(:zones_for_state).with("Veracruz").and_return(veracruz_zones)

        # Step 1: Initial detection
        described_class.call_search_mode(from: from, body: "Hola")

        # Step 2: User declines with "No"
        orchestrator = described_class.new_search_mode(from: from, body: "No")
        search_context = { detected_state: "Veracruz", stage: "region_confirmation" }

        orchestrator.send(:handle_region_confirmation_response, search_context)

        # Verify all_zones called (not zones_for_state)
        expect(ZonesService).to have_received(:all_zones)
        expect(ZonesService).not_to have_received(:zones_for_state)

        # Verify List Message sent with all zones
        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "Todas las zonas")
          )
        )

        # Verify context stored with region_scope: "all"
        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            stage: "zone_selection",
            region_scope: "all"
          }.to_json
        )
      end
    end

    context "when comparing zone lists between 'Sí' and 'No' paths" do
      it "ensures 'Sí' path shows fewer zones than 'No' path" do
        # Verify state-specific zones are fewer than all zones
        expect(veracruz_zones.length).to be < all_zones.length

        # Verify state-specific zones contain only Veracruz zones
        # (not necessarily a subset of all_zones in our test data)
        expect(veracruz_zones).to eq(["Centro Histórico", "Boca del Río", "Costa Verde"])
        expect(all_zones).to include("Centro Histórico", "Boca del Río", "Cholula", "Pachuca Centro", "Oaxaca Centro")
      end
    end
  end

  # Task 16.1: Category selection after zone selection
  describe "#handle_zone_selection_response with category list" do
    let(:from) { "5212291234567" }
    let(:body) { "Centro Histórico" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:search_context) do
      {
        detected_state: "Veracruz",
        stage: "zone_selection",
        region_scope: "state"
      }
    end

    before do
      allow(REDIS).to receive(:setex)
      allow(WhatsAppService).to receive(:send_list_message)
      allow(Rails.logger).to receive(:info)
    end

    it "sends categories List Message after zone selection" do
      orchestrator.send(:handle_zone_selection_response, search_context)

      expect(WhatsAppService).to have_received(:send_list_message).with(
        to: from,
        payload: hash_including(
          type: "list",
          header: hash_including(text: "¿Qué tipo de técnico?"),
          body: hash_including(text: "Selecciona el servicio que necesitas")
        )
      )
    end

    it "stores category_page: 1 in context" do
      orchestrator.send(:handle_zone_selection_response, search_context)

      expect(REDIS).to have_received(:setex).with(
        "client_search:#{from}",
        86_400,
        {
          detected_state: "Veracruz",
          region_scope: "state",
          selected_zone: "Centro Histórico",
          stage: "category_selection",
          category_page: 1
        }.to_json
      )
    end

    it "logs zone selection with category message sent" do
      orchestrator.send(:handle_zone_selection_response, search_context)

      expect(Rails.logger).to have_received(:info).with(
        "[ClientAssistantOrchestrator] Zone selected: Centro Histórico for client #{from}. Sent categories page 1."
      )
    end
  end

  describe "#handle_category_selection_response" do
    let(:from) { "5212291234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:search_context) do
      {
        detected_state: "Veracruz",
        region_scope: "state",
        selected_zone: "Centro Histórico",
        stage: "category_selection",
        category_page: 1
      }
    end

    before do
      allow(WhatsAppService).to receive(:send_message)
      allow(WhatsAppService).to receive(:send_list_message)
      allow(REDIS).to receive(:setex)
      allow(Rails.logger).to receive(:info)

      # Mock provider query for Task 17 implementation
      provider_relation = instance_double(ActiveRecord::Relation)
      allow(Provider).to receive(:where).and_return(provider_relation)
      allow(provider_relation).to receive(:joins).and_return(provider_relation)
      allow(provider_relation).to receive(:where).and_return(provider_relation)
      allow(provider_relation).to receive(:includes).and_return(provider_relation)
      allow(provider_relation).to receive(:distinct).and_return(provider_relation)
      allow(provider_relation).to receive(:count).and_return(5)
      allow(provider_relation).to receive(:order).and_return(provider_relation)
      allow(provider_relation).to receive(:offset).and_return(provider_relation)
      allow(provider_relation).to receive(:limit).and_return(provider_relation)
      allow(provider_relation).to receive(:empty?).and_return(false)
      allow(provider_relation).to receive(:map).and_return([])

      # Mock ZonesService for category name lookup
      allow(ZonesService).to receive(:all_categories).and_return([
        { "id" => "plomeria", "name" => "Plomería", "icon" => "🔧" },
        { "id" => "electricidad", "name" => "Electricidad", "icon" => "⚡" },
        { "id" => "construccion", "name" => "Construcción", "icon" => "🏗" }
      ])

      # Mock ListMessageBuilder
      allow(WhatsApp::ListMessageBuilder).to receive(:build_provider_results_list).and_return(
        {
          type: "list",
          header: { type: "text", text: "Técnicos disponibles" },
          body: { text: "Encontré 5 técnicos" },
          action: { button: "Ver opciones", sections: [] }
        }
      )
    end

    context "when user selects a category" do
      let(:body) { "plomeria" }

      it "queries providers and sends results List Message" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Provider).to have_received(:where).with(active: true)
        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "logs category selection with provider count" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Category selected: plomeria for client #{from}. Found 5 providers."
        )
      end

      it "stores selected category in context with provider_selection stage" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            selected_category: "plomeria",
            stage: "provider_selection",
            provider_page: 1
          }.to_json
        )
      end

      it "updates stage to provider_selection" do
        orchestrator.send(:handle_category_selection_response, search_context)

        # Verify the call was made with the correct stage
        expect(REDIS).to have_received(:setex) do |key, ttl, json_data|
          stored_context = JSON.parse(json_data, symbolize_names: true)
          expect(stored_context[:stage]).to eq("provider_selection")
        end
      end
    end

    context "when user selects electricidad category" do
      let(:body) { "electricidad" }

      it "queries providers and sends results" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Provider).to have_received(:where).with(active: true)
        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "stores electricidad in context with provider_selection stage" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            selected_category: "electricidad",
            stage: "provider_selection",
            provider_page: 1
          }.to_json
        )
      end
    end

    # Task 16.4: Handle "Ver más categorías" selection
    context "when user selects 'Ver más categorías'" do
      let(:body) { "ver_mas_categorias" }

      it "sends categories page 2 List Message" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "¿Qué tipo de técnico?")
          )
        )
      end

      it "does not send confirmation message" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(WhatsAppService).not_to have_received(:send_message)
      end

      it "updates context to category_page: 2" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            stage: "category_selection",
            category_page: 2
          }.to_json
        )
      end

      it "keeps stage as category_selection" do
        orchestrator.send(:handle_category_selection_response, search_context)

        # Verify the call was made with the correct stage
        expect(REDIS).to have_received(:setex) do |key, ttl, json_data|
          stored_context = JSON.parse(json_data, symbolize_names: true)
          expect(stored_context[:stage]).to eq("category_selection")
        end
      end

      it "preserves detected_state in context" do
        orchestrator.send(:handle_category_selection_response, search_context)

        # Verify the call was made with the correct detected_state
        expect(REDIS).to have_received(:setex) do |key, ttl, json_data|
          stored_context = JSON.parse(json_data, symbolize_names: true)
          expect(stored_context[:detected_state]).to eq("Veracruz")
        end
      end

      it "preserves region_scope in context" do
        orchestrator.send(:handle_category_selection_response, search_context)

        # Verify the call was made with the correct region_scope
        expect(REDIS).to have_received(:setex) do |key, ttl, json_data|
          stored_context = JSON.parse(json_data, symbolize_names: true)
          expect(stored_context[:region_scope]).to eq("state")
        end
      end

      it "preserves selected_zone in context" do
        orchestrator.send(:handle_category_selection_response, search_context)

        # Verify the call was made with the correct selected_zone
        expect(REDIS).to have_received(:setex) do |key, ttl, json_data|
          stored_context = JSON.parse(json_data, symbolize_names: true)
          expect(stored_context[:selected_zone]).to eq("Centro Histórico")
        end
      end

      it "logs page 2 sent" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Sent categories page 2 for client #{from}"
        )
      end

      it "does not log category selection" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Rails.logger).not_to have_received(:info).with(
          /Category selected:/
        )
      end
    end

    context "when user selects 'Ver más categorías' with different region_scope" do
      let(:body) { "ver_mas_categorias" }
      let(:search_context) do
        {
          detected_state: "Puebla",
          region_scope: "all",
          selected_zone: "Cholula",
          stage: "category_selection",
          category_page: 1
        }
      end

      it "preserves all context fields when showing page 2" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Puebla",
            region_scope: "all",
            selected_zone: "Cholula",
            stage: "category_selection",
            category_page: 2
          }.to_json
        )
      end
    end

    context "when user is already on page 2 and selects a category" do
      let(:body) { "construccion" }
      let(:search_context) do
        {
          detected_state: "Veracruz",
          region_scope: "state",
          selected_zone: "Centro Histórico",
          stage: "category_selection",
          category_page: 2
        }
      end

      it "queries providers and sends results" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Provider).to have_received(:where).with(active: true)
        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "stores selected category and updates stage to provider_selection" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            selected_category: "construccion",
            stage: "provider_selection",
            provider_page: 1
          }.to_json
        )
      end
    end

    context "when category selection is blank" do
      let(:body) { "" }

      it "sends error message" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
        )
      end

      it "does not log category selection" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Rails.logger).not_to have_received(:info)
      end

      it "does not update context" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(REDIS).not_to have_received(:setex)
      end
    end

    context "when category selection is only whitespace" do
      let(:body) { "   " }

      it "sends error message" do
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
        )
      end
    end
  end

  describe "#handle_search_flow_response with category_selection stage" do
    let(:from) { "5212291234567" }
    let(:body) { "plomeria" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(WhatsAppService).to receive(:send_message)
      allow(Rails.logger).to receive(:info)
    end

    context "when stage is category_selection" do
      let(:search_context) do
        {
          detected_state: "Veracruz",
          region_scope: "state",
          selected_zone: "Centro Histórico",
          stage: "category_selection",
          category_page: 1
        }
      end

      it "calls handle_category_selection_response" do
        allow(orchestrator).to receive(:handle_category_selection_response)

        orchestrator.send(:handle_search_flow_response, search_context)

        expect(orchestrator).to have_received(:handle_category_selection_response).with(search_context)
      end
    end
  end

  # Task 17.5: Handle provider selection
  describe "#handle_provider_selection_response" do
    let(:from) { "5212291234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:search_context) do
      {
        detected_state: "Veracruz",
        region_scope: "state",
        selected_zone: "Centro Histórico",
        selected_category: "plomeria",
        stage: "provider_selection",
        provider_page: 1
      }
    end

    before do
      allow(WhatsAppService).to receive(:send_message)
      allow(WhatsAppService).to receive(:send_list_message)
      allow(REDIS).to receive(:setex)
      allow(REDIS).to receive(:del)
      allow(Rails.logger).to receive(:info)

      # Mock provider query for pagination tests
      provider_relation = instance_double(ActiveRecord::Relation)
      allow(Provider).to receive(:where).and_return(provider_relation)
      allow(provider_relation).to receive(:joins).and_return(provider_relation)
      allow(provider_relation).to receive(:where).and_return(provider_relation)
      allow(provider_relation).to receive(:includes).and_return(provider_relation)
      allow(provider_relation).to receive(:distinct).and_return(provider_relation)
      allow(provider_relation).to receive(:count).and_return(15)
      allow(provider_relation).to receive(:left_joins).and_return(provider_relation)
      allow(provider_relation).to receive(:group).and_return(provider_relation)
      allow(provider_relation).to receive(:order).and_return(provider_relation)
      allow(provider_relation).to receive(:offset).and_return(provider_relation)
      allow(provider_relation).to receive(:limit).and_return(provider_relation)

      # Mock ZonesService for category name lookup
      allow(ZonesService).to receive(:all_categories).and_return([
        { "id" => "plomeria", "name" => "Plomería", "icon" => "🔧" }
      ])

      # Mock ListMessageBuilder
      allow(WhatsApp::ListMessageBuilder).to receive(:build_provider_results_list).and_return(
        {
          type: "list",
          header: { type: "text", text: "Técnicos disponibles" },
          body: { text: "Encontré 15 técnicos" },
          action: { button: "Ver opciones", sections: [] }
        }
      )
    end

    context "when user selects a provider" do
      let(:body) { "provider_123" }
      let(:provider) { instance_double(Provider, id: 123, name: "Miguel Hernández", phone: "5212291234567") }
      let(:client) { instance_double(Client, id: 1, phone: from, save!: true, new_record?: true) }
      let(:conversation) { instance_double(Conversation, id: 1, stage: "active", context: {}, update!: true) }

      before do
        allow(Provider).to receive(:find_by).with(id: 123).and_return(provider)
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
        allow(conversation).to receive(:client=)
        allow(conversation).to receive(:stage=)
        allow(conversation).to receive(:context=)
        allow(conversation).to receive(:last_message_at=)
      end

      it "extracts provider ID from selection" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Provider).to have_received(:find_by).with(id: 123)
      end

      it "finds or creates client record" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Client).to have_received(:find_or_initialize_by).with(phone: from)
      end

      it "creates new client if not exists" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(client).to have_received(:save!)
      end

      it "finds or creates conversation record" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Conversation).to have_received(:find_or_create_by!).with(
          provider: provider,
          phone: from,
          role: "client"
        )
      end

      it "sets conversation stage to appointment_scheduling" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(conversation).to have_received(:stage=).with("appointment_scheduling")
      end

      it "stores search context in conversation context" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(conversation).to have_received(:context=).with(
          hash_including(
            selected_zone: "Centro Histórico",
            selected_category: "plomeria",
            discovery_method: "c2a_region_based"
          )
        )
      end

      it "clears search context from Redis" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(REDIS).to have_received(:del).with("client_search:#{from}")
      end

      it "sends confirmation message" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Perfecto, seleccionaste a Miguel Hernández. Ahora vamos a agendar tu cita..."
        )
      end

      it "logs provider selection" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Provider selected: Miguel Hernández (ID: 123) for client #{from}. Transitioning to appointment flow."
        )
      end
    end

    context "when user selects a provider and client already exists" do
      let(:body) { "provider_456" }
      let(:provider) { instance_double(Provider, id: 456, name: "Juan Pérez", phone: "5212291111111") }
      let(:client) { instance_double(Client, id: 2, phone: from, save!: true, new_record?: false) }
      let(:conversation) { instance_double(Conversation, id: 2, stage: "active", context: {}, update!: true) }

      before do
        allow(Provider).to receive(:find_by).with(id: 456).and_return(provider)
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
        allow(conversation).to receive(:client=)
        allow(conversation).to receive(:stage=)
        allow(conversation).to receive(:context=)
        allow(conversation).to receive(:last_message_at=)
      end

      it "does not save existing client" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(client).not_to have_received(:save!)
      end

      it "still creates conversation and transitions to appointment flow" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Conversation).to have_received(:find_or_create_by!)
        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Perfecto, seleccionaste a Juan Pérez. Ahora vamos a agendar tu cita..."
        )
      end
    end

    context "when user selects a provider and conversation already exists" do
      let(:body) { "provider_789" }
      let(:provider) { instance_double(Provider, id: 789, name: "Carlos López", phone: "5212292222222") }
      let(:client) { instance_double(Client, id: 3, phone: from, save!: true, new_record?: false) }
      let(:conversation) do
        instance_double(
          Conversation,
          id: 3,
          stage: "escalated",
          context: { previous_data: "value" },
          update!: true
        )
      end

      before do
        allow(Provider).to receive(:find_by).with(id: 789).and_return(provider)
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_return(conversation)
      end

      it "updates existing conversation stage" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(conversation).to have_received(:update!).with(
          hash_including(
            stage: "appointment_scheduling"
          )
        )
      end

      it "merges new context with existing context" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(conversation).to have_received(:update!).with(
          hash_including(
            context: hash_including(
              selected_zone: "Centro Histórico",
              selected_category: "plomeria",
              discovery_method: "c2a_region_based"
            )
          )
        )
      end
    end

    context "when provider is not found" do
      let(:body) { "provider_999" }

      before do
        allow(Provider).to receive(:find_by).with(id: 999).and_return(nil)
        allow(Client).to receive(:find_or_initialize_by)
        allow(Conversation).to receive(:find_or_create_by!)
      end

      it "sends error message" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Lo siento, no pude encontrar ese técnico. ¿Puedes seleccionar otro?"
        )
      end

      it "does not create client or conversation" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Client).not_to have_received(:find_or_initialize_by)
        expect(Conversation).not_to have_received(:find_or_create_by!)
      end

      it "does not clear search context" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(REDIS).not_to have_received(:del)
      end

      it "does not log provider selection" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Rails.logger).not_to have_received(:info).with(/Provider selected:/)
      end
    end

    context "when user selects 'Ver más técnicos' for page 2" do
      let(:body) { "ver_mas_providers_page_2" }

      before do
        allow(Client).to receive(:find_or_initialize_by)
        allow(Conversation).to receive(:find_or_create_by!)
      end

      it "extracts page number from selection" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Provider).to have_received(:where).with(active: true)
      end

      it "sends provider results for page 2" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "updates context with new page number" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            selected_category: "plomeria",
            stage: "provider_selection",
            provider_page: 2
          }.to_json
        )
      end

      it "logs page 2 sent" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Sent provider results page 2 for client #{from}"
        )
      end

      it "does not transition to appointment flow" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Client).not_to have_received(:find_or_initialize_by)
        expect(Conversation).not_to have_received(:find_or_create_by!)
      end
    end

    context "when user selects 'Ver más técnicos' for page 3" do
      let(:body) { "ver_mas_providers_page_3" }

      it "sends provider results for page 3" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "updates context with page 3" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(REDIS).to have_received(:setex).with(
          "client_search:#{from}",
          86_400,
          {
            detected_state: "Veracruz",
            region_scope: "state",
            selected_zone: "Centro Histórico",
            selected_category: "plomeria",
            stage: "provider_selection",
            provider_page: 3
          }.to_json
        )
      end
    end

    context "when provider selection is blank" do
      let(:body) { "" }

      before do
        allow(Client).to receive(:find_or_initialize_by)
        allow(Conversation).to receive(:find_or_create_by!)
      end

      it "sends error message" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
        )
      end

      it "does not create client or conversation" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Client).not_to have_received(:find_or_initialize_by)
        expect(Conversation).not_to have_received(:find_or_create_by!)
      end
    end

    context "when provider selection is only whitespace" do
      let(:body) { "   " }

      it "sends error message" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
        )
      end
    end

    context "when provider selection has invalid format" do
      let(:body) { "invalid_selection" }

      before do
        allow(Provider).to receive(:find_by)
        allow(Client).to receive(:find_or_initialize_by)
        allow(Conversation).to receive(:find_or_create_by!)
      end

      it "sends error message" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
        )
      end

      it "does not attempt to find provider" do
        orchestrator.send(:handle_provider_selection_response, search_context)

        expect(Provider).not_to have_received(:find_by)
      end
    end
  end

  describe "#transition_to_appointment_flow" do
    let(:from) { "5212291234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:provider) { instance_double(Provider, id: 123, name: "Miguel Hernández", phone: "5212291234567") }
    let(:search_context) do
      {
        detected_state: "Veracruz",
        region_scope: "state",
        selected_zone: "Centro Histórico",
        selected_category: "plomeria"
      }
    end

    before do
      allow(WhatsAppService).to receive(:send_message)
      allow(REDIS).to receive(:del)
      allow(Rails.logger).to receive(:info)
    end

    context "when creating new client and conversation" do
      let(:client) { instance_double(Client, id: 1, phone: from, save!: true, new_record?: true) }
      let(:conversation) { instance_double(Conversation, id: 1, stage: "active", context: {}, update!: true) }

      before do
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
        allow(conversation).to receive(:client=)
        allow(conversation).to receive(:stage=)
        allow(conversation).to receive(:context=)
        allow(conversation).to receive(:last_message_at=)
        allow(conversation).to receive(:context).and_return({})
      end

      it "creates new client record" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(client).to have_received(:save!)
      end

      it "logs client creation" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Created new client record for #{from}"
        )
      end

      it "creates conversation with appointment_scheduling stage" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(conversation).to have_received(:stage=).with("appointment_scheduling")
      end

      it "stores discovery context in conversation" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(conversation).to have_received(:context=).with(
          selected_zone: "Centro Histórico",
          selected_category: "plomeria",
          discovery_method: "c2a_region_based"
        )
      end

      it "clears Redis search context" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(REDIS).to have_received(:del).with("client_search:#{from}")
      end

      it "sends confirmation message with provider name" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Perfecto, seleccionaste a Miguel Hernández. Ahora vamos a agendar tu cita..."
        )
      end
    end

    context "when client already exists" do
      let(:client) { instance_double(Client, id: 2, phone: from, save!: true, new_record?: false) }
      let(:conversation) { instance_double(Conversation, id: 2, stage: "active", context: {}, update!: true) }

      before do
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
        allow(conversation).to receive(:client=)
        allow(conversation).to receive(:stage=)
        allow(conversation).to receive(:context=)
        allow(conversation).to receive(:last_message_at=)
        allow(conversation).to receive(:context).and_return({})
      end

      it "does not save existing client" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(client).not_to have_received(:save!)
      end

      it "does not log client creation" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).not_to have_received(:info).with(/Created new client/)
      end

      it "still creates conversation and sends confirmation" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Conversation).to have_received(:find_or_create_by!)
        expect(WhatsAppService).to have_received(:send_message)
      end
    end

    context "when conversation already exists with different stage" do
      let(:client) { instance_double(Client, id: 3, phone: from, save!: true, new_record?: false) }
      let(:conversation) do
        instance_double(
          Conversation,
          id: 3,
          stage: "escalated",
          context: { previous_key: "previous_value" },
          update!: true
        )
      end

      before do
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_return(conversation)
      end

      it "updates conversation stage to appointment_scheduling" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(conversation).to have_received(:update!).with(
          hash_including(stage: "appointment_scheduling")
        )
      end

      it "merges search context with existing context" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(conversation).to have_received(:update!).with(
          hash_including(
            context: hash_including(
              selected_zone: "Centro Histórico",
              selected_category: "plomeria",
              discovery_method: "c2a_region_based"
            )
          )
        )
      end

      it "updates last_message_at timestamp" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(conversation).to have_received(:update!).with(
          hash_including(:last_message_at)
        )
      end
    end

    context "when conversation already exists with appointment_scheduling stage" do
      let(:client) { instance_double(Client, id: 4, phone: from, save!: true, new_record?: false) }
      let(:conversation) do
        instance_double(
          Conversation,
          id: 4,
          stage: "appointment_scheduling",
          context: { old_zone: "Old Zone" },
          update!: true
        )
      end

      before do
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_return(conversation)
      end

      it "still updates conversation to refresh context" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        # The update! should be called even if stage is already correct
        expect(conversation).to have_received(:update!)
      end

      it "updates context with new search data" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(conversation).to have_received(:update!).with(
          hash_including(
            context: hash_including(
              selected_zone: "Centro Histórico",
              selected_category: "plomeria"
            )
          )
        )
      end
    end
  end

  describe "#clear_search_context" do
    let(:from) { "5212291234567" }
    let(:body) { "test" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(REDIS).to receive(:del)
    end

    it "deletes search context from Redis" do
      orchestrator.send(:clear_search_context)

      expect(REDIS).to have_received(:del).with("client_search:#{from}")
    end

    it "uses correct Redis key format" do
      orchestrator.send(:clear_search_context)

      expect(REDIS).to have_received(:del).with("client_search:5212291234567")
    end
  end

  describe "#handle_search_flow_response with provider_selection stage" do
    let(:from) { "5212291234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    context "when stage is provider_selection" do
      let(:search_context) do
        {
          detected_state: "Veracruz",
          region_scope: "state",
          selected_zone: "Centro Histórico",
          selected_category: "plomeria",
          stage: "provider_selection",
          provider_page: 1
        }
      end

      it "calls handle_provider_selection_response" do
        allow(orchestrator).to receive(:handle_provider_selection_response)

        orchestrator.send(:handle_search_flow_response, search_context)

        expect(orchestrator).to have_received(:handle_provider_selection_response).with(search_context)
      end
    end
  end
end
