# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientAssistantOrchestrator, type: :service do
  describe "Provider Results Pagination (Task 17.4)" do
    let(:from) { "5212345678901" }
    let(:provider) { nil } # No provider for search mode
    let(:body) { "" } # Default body, overridden in specific contexts
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      # Mock Redis for search context storage
      allow(REDIS).to receive(:setex)
      allow(REDIS).to receive(:get).and_return(nil)

      # Mock WhatsAppService
      allow(WhatsAppService).to receive(:send_message)
      allow(WhatsAppService).to receive(:send_list_message)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
    end

    describe "#handle_provider_selection_response" do
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

      context "when user selects 'Ver más técnicos'" do
        let(:body) { "ver_mas_providers_page_2" }
        let!(:providers) do
          # Create 15 providers to test pagination
          (1..15).map do |i|
            instance_double(
              Provider,
              id: i,
              name: "Técnico #{i}",
              city: "Veracruz",
              active: true,
              reviews: instance_double(ActiveRecord::Relation, average: 4.5),
              provider_categories: [ instance_double(ProviderCategory, primary: true, name: "Plomería") ]
            )
          end
        end

        before do
          # Mock provider query
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
          allow(provider_relation).to receive(:map).and_return(providers[10..14]) # Page 2 results

          # Mock ZonesService for category name lookup
          allow(ZonesService).to receive(:all_categories).and_return([
            { "id" => "plomeria", "name" => "Plomería", "icon" => "🔧" }
          ])

          # Mock Redis to return search context
          allow(REDIS).to receive(:get).with("client_search:#{from}").and_return(search_context.to_json)
        end

        it "queries providers again" do
          expect(Provider).to receive(:where).with(active: true)

          orchestrator.send(:handle_provider_selection_response, search_context)
        end

        it "sends provider results for page 2" do
          expect(WhatsAppService).to receive(:send_list_message) do |args|
            expect(args[:to]).to eq(from)
            expect(args[:payload]).to be_a(Hash)
            expect(args[:payload][:type]).to eq("list")
          end

          orchestrator.send(:handle_provider_selection_response, search_context)
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

        it "logs the page number" do
          expect(Rails.logger).to receive(:info).with(
            "[ClientAssistantOrchestrator] Sent provider results page 2 for client #{from}"
          )

          orchestrator.send(:handle_provider_selection_response, search_context)
        end
      end

      context "when user selects a provider" do
        let(:body) { "provider_123" }
        let(:provider_instance) do
          instance_double(
            Provider,
            id: 123,
            name: "Miguel Hernández",
            city: "Veracruz"
          )
        end

        before do
          allow(Provider).to receive(:find_by).with(id: 123).and_return(provider_instance)
        end

        it "finds the provider by ID" do
          expect(Provider).to receive(:find_by).with(id: 123)

          orchestrator.send(:handle_provider_selection_response, search_context)
        end

        it "sends confirmation message" do
          expect(WhatsAppService).to receive(:send_message).with(
            to: from,
            message: "Perfecto, seleccionaste a Miguel Hernández. Ahora vamos a agendar tu cita..."
          )

          orchestrator.send(:handle_provider_selection_response, search_context)
        end

        it "logs the provider selection" do
          expect(Rails.logger).to receive(:info).with(
            "[ClientAssistantOrchestrator] Provider selected: Miguel Hernández (ID: 123) for client #{from}"
          )

          orchestrator.send(:handle_provider_selection_response, search_context)
        end
      end

      context "when provider ID is invalid" do
        let(:body) { "provider_999" }

        before do
          allow(Provider).to receive(:find_by).with(id: 999).and_return(nil)
        end

        it "sends error message" do
          expect(WhatsAppService).to receive(:send_message).with(
            to: from,
            message: "Lo siento, no pude encontrar ese técnico. ¿Puedes seleccionar otro?"
          )

          orchestrator.send(:handle_provider_selection_response, search_context)
        end
      end

      context "when selection is invalid" do
        let(:body) { "invalid_selection" }

        it "sends error message" do
          expect(WhatsAppService).to receive(:send_message).with(
            to: from,
            message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
          )

          orchestrator.send(:handle_provider_selection_response, search_context)
        end
      end

      context "when body is blank" do
        let(:body) { "" }

        it "sends error message" do
          expect(WhatsAppService).to receive(:send_message).with(
            to: from,
            message: "No pude identificar tu selección. ¿Puedes seleccionar una opción de la lista?"
          )

          orchestrator.send(:handle_provider_selection_response, search_context)
        end
      end
    end

    describe "#query_providers" do
      let!(:active_provider_1) do
        instance_double(
          Provider,
          id: 1,
          name: "Provider 1",
          city: "Veracruz - Centro Histórico",
          active: true
        )
      end

      let!(:active_provider_2) do
        instance_double(
          Provider,
          id: 2,
          name: "Provider 2",
          city: "Veracruz - Centro Histórico",
          active: true
        )
      end

      let!(:inactive_provider) do
        instance_double(
          Provider,
          id: 3,
          name: "Inactive Provider",
          city: "Veracruz - Centro Histórico",
          active: false
        )
      end

      before do
        # Mock ActiveRecord query chain
        provider_relation = instance_double(ActiveRecord::Relation)
        allow(Provider).to receive(:where).with(active: true).and_return(provider_relation)
        allow(provider_relation).to receive(:joins).with(:provider_categories).and_return(provider_relation)
        allow(provider_relation).to receive(:where).with(provider_categories: { slug: "plomeria" }).and_return(provider_relation)
        allow(provider_relation).to receive(:includes).with(:reviews, :provider_categories).and_return(provider_relation)
        allow(provider_relation).to receive(:distinct).and_return(provider_relation)
        allow(provider_relation).to receive(:where).with("city ILIKE ?", "%Centro Histórico%").and_return(provider_relation)
        allow(provider_relation).to receive(:count).and_return(2)
        allow(provider_relation).to receive(:order).with("RANDOM()").and_return(provider_relation)
      end

      it "queries active providers only" do
        expect(Provider).to receive(:where).with(active: true)

        orchestrator.send(:query_providers, zone: "Centro Histórico", category: "plomeria")
      end

      it "filters by category slug" do
        provider_relation = instance_double(ActiveRecord::Relation)
        allow(Provider).to receive(:where).and_return(provider_relation)
        allow(provider_relation).to receive(:joins).and_return(provider_relation)
        allow(provider_relation).to receive(:where).and_return(provider_relation)
        allow(provider_relation).to receive(:includes).and_return(provider_relation)
        allow(provider_relation).to receive(:distinct).and_return(provider_relation)
        allow(provider_relation).to receive(:count).and_return(2)
        allow(provider_relation).to receive(:order).and_return(provider_relation)

        expect(provider_relation).to receive(:where).with(provider_categories: { slug: "plomeria" })

        orchestrator.send(:query_providers, zone: "Centro Histórico", category: "plomeria")
      end

      it "filters by zone (city ILIKE)" do
        provider_relation = instance_double(ActiveRecord::Relation)
        allow(Provider).to receive(:where).and_return(provider_relation)
        allow(provider_relation).to receive(:joins).and_return(provider_relation)
        allow(provider_relation).to receive(:where).with(provider_categories: { slug: "plomeria" }).and_return(provider_relation)
        allow(provider_relation).to receive(:includes).and_return(provider_relation)
        allow(provider_relation).to receive(:distinct).and_return(provider_relation)
        allow(provider_relation).to receive(:where).with("city ILIKE ?", "%Centro Histórico%").and_return(provider_relation)
        allow(provider_relation).to receive(:count).and_return(2)
        allow(provider_relation).to receive(:order).and_return(provider_relation)

        expect(provider_relation).to receive(:where).with("city ILIKE ?", "%Centro Histórico%")

        orchestrator.send(:query_providers, zone: "Centro Histórico", category: "plomeria")
      end

      context "when there are <= 10 providers" do
        before do
          provider_relation = instance_double(ActiveRecord::Relation)
          allow(Provider).to receive(:where).and_return(provider_relation)
          allow(provider_relation).to receive(:joins).and_return(provider_relation)
          allow(provider_relation).to receive(:where).and_return(provider_relation)
          allow(provider_relation).to receive(:includes).and_return(provider_relation)
          allow(provider_relation).to receive(:distinct).and_return(provider_relation)
          allow(provider_relation).to receive(:count).and_return(8)
          allow(provider_relation).to receive(:order).and_return(provider_relation)
        end

        it "orders randomly" do
          provider_relation = instance_double(ActiveRecord::Relation)
          allow(Provider).to receive(:where).and_return(provider_relation)
          allow(provider_relation).to receive(:joins).and_return(provider_relation)
          allow(provider_relation).to receive(:where).and_return(provider_relation)
          allow(provider_relation).to receive(:includes).and_return(provider_relation)
          allow(provider_relation).to receive(:distinct).and_return(provider_relation)
          allow(provider_relation).to receive(:count).and_return(8)

          expect(provider_relation).to receive(:order).with("RANDOM()")

          orchestrator.send(:query_providers, zone: "Centro Histórico", category: "plomeria")
        end
      end

      context "when there are > 10 providers" do
        before do
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
        end

        it "orders by average rating DESC, then random" do
          provider_relation = instance_double(ActiveRecord::Relation)
          allow(Provider).to receive(:where).and_return(provider_relation)
          allow(provider_relation).to receive(:joins).and_return(provider_relation)
          allow(provider_relation).to receive(:where).and_return(provider_relation)
          allow(provider_relation).to receive(:includes).and_return(provider_relation)
          allow(provider_relation).to receive(:distinct).and_return(provider_relation)
          allow(provider_relation).to receive(:count).and_return(15)
          allow(provider_relation).to receive(:left_joins).with(:reviews).and_return(provider_relation)
          allow(provider_relation).to receive(:group).with("providers.id").and_return(provider_relation)

          expect(provider_relation).to receive(:order).with(kind_of(String))

          orchestrator.send(:query_providers, zone: "Centro Histórico", category: "plomeria")
        end
      end
    end

    describe "#send_provider_results" do
      let(:providers) do
        provider_relation = instance_double(ActiveRecord::Relation)
        allow(provider_relation).to receive(:count).and_return(12)
        allow(provider_relation).to receive(:offset).and_return(provider_relation)
        allow(provider_relation).to receive(:limit).and_return(provider_relation)
        allow(provider_relation).to receive(:map).and_return([])
        provider_relation
      end

      before do
        # Mock ZonesService for category name lookup
        allow(ZonesService).to receive(:all_categories).and_return([
          { "id" => "plomeria", "name" => "Plomería", "icon" => "🔧" }
        ])

        # Mock ListMessageBuilder
        allow(WhatsApp::ListMessageBuilder).to receive(:build_provider_results_list).and_return(
          {
            type: "list",
            header: { type: "text", text: "Técnicos disponibles" },
            body: { text: "Encontré 12 técnicos de Plomería en Centro Histórico" },
            action: { button: "Ver opciones", sections: [] }
          }
        )
      end

      it "looks up category name from ZonesService" do
        expect(ZonesService).to receive(:all_categories)

        orchestrator.send(
          :send_provider_results,
          providers: providers,
          page: 1,
          zone: "Centro Histórico",
          category: "plomeria"
        )
      end

      it "builds provider results list message" do
        expect(WhatsApp::ListMessageBuilder).to receive(:build_provider_results_list).with(
          providers,
          page: 1,
          zone: "Centro Histórico",
          category: "Plomería"
        )

        orchestrator.send(
          :send_provider_results,
          providers: providers,
          page: 1,
          zone: "Centro Histórico",
          category: "plomeria"
        )
      end

      it "sends list message via WhatsAppService" do
        expect(WhatsAppService).to receive(:send_list_message).with(
          to: from,
          payload: {
            type: "list",
            header: { type: "text", text: "Técnicos disponibles" },
            body: { text: "Encontré 12 técnicos de Plomería en Centro Histórico" },
            action: { button: "Ver opciones", sections: [] }
          }
        )

        orchestrator.send(
          :send_provider_results,
          providers: providers,
          page: 1,
          zone: "Centro Histórico",
          category: "plomeria"
        )
      end

      context "when category is not found in ZonesService" do
        before do
          allow(ZonesService).to receive(:all_categories).and_return([])
        end

        it "uses category slug as fallback" do
          expect(WhatsApp::ListMessageBuilder).to receive(:build_provider_results_list).with(
            providers,
            page: 1,
            zone: "Centro Histórico",
            category: "plomeria" # Falls back to slug
          )

          orchestrator.send(
            :send_provider_results,
            providers: providers,
            page: 1,
            zone: "Centro Histórico",
            category: "plomeria"
          )
        end
      end
    end

    describe "Integration: Category selection to provider results with pagination" do
      let(:body) { "plomeria" }
      let(:search_context) do
        {
          detected_state: "Veracruz",
          region_scope: "state",
          selected_zone: "Centro Histórico",
          stage: "category_selection",
          category_page: 1
        }
      end

      let!(:providers) do
        # Create 12 providers to test pagination
        (1..12).map do |i|
          instance_double(
            Provider,
            id: i,
            name: "Técnico #{i}",
            city: "Veracruz - Centro Histórico",
            active: true,
            reviews: instance_double(ActiveRecord::Relation, average: 4.5),
            provider_categories: [ instance_double(ProviderCategory, primary: true, name: "Plomería") ]
          )
        end
      end

      before do
        # Mock Redis to return search context
        allow(REDIS).to receive(:get).with("client_search:#{from}").and_return(search_context.to_json)

        # Mock provider query
        provider_relation = instance_double(ActiveRecord::Relation)
        allow(Provider).to receive(:where).and_return(provider_relation)
        allow(provider_relation).to receive(:joins).and_return(provider_relation)
        allow(provider_relation).to receive(:where).and_return(provider_relation)
        allow(provider_relation).to receive(:includes).and_return(provider_relation)
        allow(provider_relation).to receive(:distinct).and_return(provider_relation)
        allow(provider_relation).to receive(:count).and_return(12)
        allow(provider_relation).to receive(:left_joins).and_return(provider_relation)
        allow(provider_relation).to receive(:group).and_return(provider_relation)
        allow(provider_relation).to receive(:order).and_return(provider_relation)
        allow(provider_relation).to receive(:offset).and_return(provider_relation)
        allow(provider_relation).to receive(:limit).and_return(provider_relation)
        allow(provider_relation).to receive(:map).and_return(providers.first(10))
        allow(provider_relation).to receive(:empty?).and_return(false)

        # Mock ZonesService
        allow(ZonesService).to receive(:all_categories).and_return([
          { "id" => "plomeria", "name" => "Plomería", "icon" => "🔧" }
        ])

        # Mock ListMessageBuilder
        allow(WhatsApp::ListMessageBuilder).to receive(:build_provider_results_list).and_return(
          {
            type: "list",
            header: { type: "text", text: "Técnicos disponibles" },
            body: { text: "Encontré 12 técnicos de Plomería en Centro Histórico" },
            action: {
              button: "Ver opciones",
              sections: [
                {
                  title: "Selecciona uno",
                  rows: [
                    { id: "provider_1", title: "Técnico 1 ⭐ 4.5" },
                    { id: "ver_mas_providers_page_2", title: "Ver más técnicos" }
                  ]
                }
              ]
            }
          }
        )
      end

      it "queries providers and sends results with pagination option" do
        expect(Provider).to receive(:where).with(active: true)
        expect(WhatsAppService).to receive(:send_list_message)

        orchestrator.send(:handle_category_selection_response, search_context)
      end

      it "stores provider selection context with page 1" do
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
    end
  end
end
