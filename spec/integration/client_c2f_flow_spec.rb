# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "Client C2F Flow with Telegram Notification", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:client_phone_number_id) { "987654321" }
  let(:client_phone) { "5219511234567" }
  let(:bot_token) { "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" }
  let(:chat_id) { "-1001234567890" }
  let(:telegram_url) { "https://api.telegram.org/bot#{bot_token}/sendMessage" }

  before do
    # Set environment variables
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_CLIENT_PHONE_NUMBER_ID").and_return(client_phone_number_id)
    allow(ENV).to receive(:[]).with("WHATSAPP_PROVIDER_PHONE_NUMBER_ID").and_return("123456789")
    allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(bot_token)
    allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(chat_id)

    # Freeze time for consistent timestamp testing
    travel_to Time.zone.local(2026, 5, 21, 10, 30, 0)

    # Mock WhatsAppService to prevent actual API calls
    allow(WhatsAppService).to receive(:send_message).and_return(nil)
    allow(WhatsAppService).to receive(:send_list_message).and_return(nil)

    # Mock ZonesService
    allow(ZonesService).to receive(:all_categories).and_return([
      { "id" => "plomeria", "name" => "Plomería", "icon" => "🔧" },
      { "id" => "electricidad", "name" => "Electricidad", "icon" => "⚡" },
      { "id" => "construccion", "name" => "Construcción y obra", "icon" => "🏗" }
    ])

    # Mock REDIS for search context storage
    allow(REDIS).to receive(:get).and_return(nil)
    allow(REDIS).to receive(:setex).and_return("OK")

    clear_enqueued_jobs
  end

  after do
    travel_back
  end

  describe "C2F flow: No providers available in selected zone and category" do
    context "when client selects category but no providers exist" do
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
        # Mock REDIS to return search context
        allow(REDIS).to receive(:get).with("client_search:#{client_phone}").and_return(search_context.to_json)

        # Ensure no providers exist for this zone and category
        # This simulates the C2F scenario
        allow(Provider).to receive(:where).and_return(Provider.none)
      end

      context "when Telegram is properly configured and API succeeds" do
        let(:success_response) do
          {
            ok: true,
            result: {
              message_id: 123,
              chat: { id: chat_id.to_i, type: "group" },
              date: 1716287400,
              text: "notification text"
            }
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .with(
              body: hash_including(
                chat_id: chat_id,
                text: /Nueva solicitud sin técnico/
              ),
              headers: { "Content-Type" => "application/json" }
            )
            .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })
        end

        it "sends unavailable message to client" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WhatsAppService).to have_received(:send_message).with(
            to: client_phone,
            message: "Lo siento, aún no tenemos técnicos de plomeria en Centro Histórico. " \
                     "¿Quieres que te avisemos cuando tengamos uno disponible?"
          )
        end

        it "creates or finds Client record" do
          expect do
            orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
            orchestrator.send(:handle_category_selection_response, search_context)
          end.to change(Client, :count).by(1)

          client = Client.find_by(phone: client_phone)
          expect(client).to be_present
          expect(client.phone).to eq(client_phone)
        end

        it "does not create duplicate Client records on subsequent calls" do
          # First call creates the client
          orchestrator1 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator1.send(:handle_category_selection_response, search_context)

          # Second call should find existing client
          expect do
            orchestrator2 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "electricidad")
            orchestrator2.send(:handle_category_selection_response, search_context)
          end.not_to change(Client, :count)
        end

        it "sends Telegram notification with correct category name" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            expect(body["chat_id"]).to eq(chat_id)
            expect(body["text"]).to include("🔔 Nueva solicitud sin técnico")
            expect(body["text"]).to include("📱 #{client_phone}")
            expect(body["text"]).to include("🔧 Plomería") # Category name, not ID
            expect(body["text"]).to include("📍 Centro Histórico")
            expect(body["text"]).to include("⏰ 21/05/2026 10:30")
          }
        end

        it "uses category name from ZonesService, not category ID" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "electricidad")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            # Should show "Electricidad" not "electricidad"
            expect(body["text"]).to include("🔧 Electricidad")
            expect(body["text"]).not_to include("electricidad")
          }
        end

        it "logs C2F flow completion with client ID and Telegram attempt" do
          allow(Rails.logger).to receive(:info)

          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          client = Client.find_by(phone: client_phone)
          expect(Rails.logger).to have_received(:info).with(
            "[ClientAssistantOrchestrator] No providers found for plomeria in Centro Histórico. " \
            "Client record created/found: #{client.id}. Telegram notification attempted."
          )
        end

        it "does not send provider results List Message" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WhatsAppService).not_to have_received(:send_list_message)
        end

        it "does not store provider_selection stage in context" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          # Should not update context to provider_selection stage
          expect(REDIS).not_to have_received(:setex).with(
            "client_search:#{client_phone}",
            anything,
            hash_including(stage: "provider_selection")
          )
        end
      end

      context "when Telegram API fails" do
        let(:error_response) do
          {
            ok: false,
            error_code: 500,
            description: "Internal Server Error"
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 500, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "still sends unavailable message to client" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WhatsAppService).to have_received(:send_message).with(
            to: client_phone,
            message: /aún no tenemos técnicos/
          )
        end

        it "still creates Client record" do
          expect do
            orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
            orchestrator.send(:handle_category_selection_response, search_context)
          end.to change(Client, :count).by(1)
        end

        it "logs error but does not raise exception" do
          allow(Rails.logger).to receive(:error)
          allow(Rails.logger).to receive(:info)

          expect do
            orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
            orchestrator.send(:handle_category_selection_response, search_context)
          end.not_to raise_error

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Telegram Server Error \(500\)/)
          )
        end

        it "logs C2F flow completion even when Telegram fails" do
          allow(Rails.logger).to receive(:info)
          allow(Rails.logger).to receive(:error)

          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(Rails.logger).to have_received(:info).with(
            a_string_matching(/No providers found.*Telegram notification attempted/)
          )
        end

        it "completes C2F flow without blocking" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")

          # Should complete successfully despite Telegram failure
          expect do
            orchestrator.send(:handle_category_selection_response, search_context)
          end.not_to raise_error

          # Verify client was created
          expect(Client.find_by(phone: client_phone)).to be_present

          # Verify message was sent
          expect(WhatsAppService).to have_received(:send_message)
        end
      end

      context "when Telegram is not configured" do
        before do
          allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(nil)
          allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(nil)
        end

        it "still sends unavailable message to client" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WhatsAppService).to have_received(:send_message).with(
            to: client_phone,
            message: /aún no tenemos técnicos/
          )
        end

        it "still creates Client record" do
          expect do
            orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
            orchestrator.send(:handle_category_selection_response, search_context)
          end.to change(Client, :count).by(1)
        end

        it "logs warning about missing Telegram configuration" do
          allow(Rails.logger).to receive(:warn)
          allow(Rails.logger).to receive(:info)

          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(Rails.logger).to have_received(:warn).with(
            a_string_matching(/Telegram not configured.*Missing TELEGRAM_BOT_TOKEN/)
          )
        end

        it "does not make HTTP request to Telegram" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WebMock).not_to have_requested(:post, /api\.telegram\.org/)
        end

        it "logs C2F flow completion" do
          allow(Rails.logger).to receive(:info)
          allow(Rails.logger).to receive(:warn)

          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(Rails.logger).to have_received(:info).with(
            a_string_matching(/No providers found.*Telegram notification attempted/)
          )
        end
      end

      context "when category is not found in ZonesService" do
        before do
          # Mock ZonesService to return empty categories
          allow(ZonesService).to receive(:all_categories).and_return([])

          stub_request(:post, telegram_url)
            .to_return(status: 200, body: { ok: true }.to_json)
        end

        it "uses category ID as fallback in Telegram notification" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "unknown_category")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            # Should use category ID when name not found
            expect(body["text"]).to include("🔧 unknown_category")
          }
        end

        it "still completes C2F flow successfully" do
          expect do
            orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "unknown_category")
            orchestrator.send(:handle_category_selection_response, search_context)
          end.not_to raise_error

          expect(Client.find_by(phone: client_phone)).to be_present
        end
      end

      context "when multiple categories are unavailable in same session" do
        let(:success_response) do
          { ok: true, result: { message_id: 123 } }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 200, body: success_response)
        end

        it "sends separate Telegram notifications for each category" do
          # First category
          orchestrator1 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator1.send(:handle_category_selection_response, search_context)

          # Second category
          orchestrator2 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "electricidad")
          orchestrator2.send(:handle_category_selection_response, search_context)

          expect(WebMock).to have_requested(:post, telegram_url).twice
        end

        it "sends separate unavailable messages to client" do
          orchestrator1 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator1.send(:handle_category_selection_response, search_context)

          orchestrator2 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "electricidad")
          orchestrator2.send(:handle_category_selection_response, search_context)

          expect(WhatsAppService).to have_received(:send_message).twice
        end

        it "does not create duplicate Client records" do
          expect do
            orchestrator1 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
            orchestrator1.send(:handle_category_selection_response, search_context)

            orchestrator2 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "electricidad")
            orchestrator2.send(:handle_category_selection_response, search_context)
          end.to change(Client, :count).by(1) # Only one client created
        end
      end

      context "when different zones have no providers" do
        let(:success_response) do
          { ok: true, result: { message_id: 123 } }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 200, body: success_response)
        end

        it "sends Telegram notification with correct zone for each request" do
          # First zone
          context1 = search_context.merge(selected_zone: "Centro Histórico")
          orchestrator1 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator1.send(:handle_category_selection_response, context1)

          # Second zone
          context2 = search_context.merge(selected_zone: "Boca del Río")
          orchestrator2 = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator2.send(:handle_category_selection_response, context2)

          # Verify Centro Histórico notification
          expect(WebMock).to have_requested(:post, telegram_url).with { |req|
            body = JSON.parse(req.body)
            body["text"].include?("📍 Centro Histórico")
          }.once

          # Verify Boca del Río notification
          expect(WebMock).to have_requested(:post, telegram_url).with { |req|
            body = JSON.parse(req.body)
            body["text"].include?("📍 Boca del Río")
          }.once
        end
      end

      context "when Client record already exists with additional data" do
        let!(:existing_client) do
          Client.create!(
            phone: client_phone,
            name: "Mariana López",
            rating: 4.5
          )
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 200, body: { ok: true }.to_json)
        end

        it "finds existing Client record without creating new one" do
          expect do
            orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
            orchestrator.send(:handle_category_selection_response, search_context)
          end.not_to change(Client, :count)
        end

        it "preserves existing Client data" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          client = Client.find_by(phone: client_phone)
          expect(client.name).to eq("Mariana López")
          expect(client.rating).to eq(4.5)
        end

        it "includes Client name in Telegram notification if available" do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            expect(body["text"]).to include("👤 Mariana López")
          }
        end
      end
    end

    context "when providers exist (not C2F flow)" do
      let(:search_context) do
        {
          detected_state: "Veracruz",
          region_scope: "state",
          selected_zone: "Centro Histórico",
          stage: "category_selection",
          category_page: 1
        }
      end

      let!(:provider) do
        Provider.create!(
          name: "Miguel Hernández",
          phone: "5219511111111",
          active: true,
          city: "Centro Histórico"
        )
      end

      before do
        # Mock REDIS to return search context
        allow(REDIS).to receive(:get).with("client_search:#{client_phone}").and_return(search_context.to_json)

        # Mock provider query to return providers
        provider_relation = instance_double(ActiveRecord::Relation)
        allow(Provider).to receive(:where).and_return(provider_relation)
        allow(provider_relation).to receive(:joins).and_return(provider_relation)
        allow(provider_relation).to receive(:where).and_return(provider_relation)
        allow(provider_relation).to receive(:includes).and_return(provider_relation)
        allow(provider_relation).to receive(:distinct).and_return(provider_relation)
        allow(provider_relation).to receive(:count).and_return(1)
        allow(provider_relation).to receive(:order).and_return(provider_relation)
        allow(provider_relation).to receive(:offset).and_return(provider_relation)
        allow(provider_relation).to receive(:limit).and_return(provider_relation)
        allow(provider_relation).to receive(:empty?).and_return(false)
        allow(provider_relation).to receive(:map).and_return([provider])

        # Mock ListMessageBuilder
        allow(WhatsApp::ListMessageBuilder).to receive(:build_provider_results_list).and_return(
          {
            type: "list",
            header: { type: "text", text: "Técnicos disponibles" },
            body: { text: "Encontré 1 técnico" },
            action: { button: "Ver opciones", sections: [] }
          }
        )

        stub_request(:post, telegram_url)
          .to_return(status: 200, body: { ok: true }.to_json)
      end

      it "does not send unavailable message" do
        orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(WhatsAppService).not_to have_received(:send_message).with(
          to: client_phone,
          message: /aún no tenemos técnicos/
        )
      end

      it "does not create Client record" do
        expect do
          orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
          orchestrator.send(:handle_category_selection_response, search_context)
        end.not_to change(Client, :count)
      end

      it "does not send Telegram notification" do
        orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(WebMock).not_to have_requested(:post, telegram_url)
      end

      it "sends provider results List Message" do
        orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "logs provider found message, not C2F message" do
        allow(Rails.logger).to receive(:info)

        orchestrator = ClientAssistantOrchestrator.new_search_mode(from: client_phone, body: "plomeria")
        orchestrator.send(:handle_category_selection_response, search_context)

        expect(Rails.logger).to have_received(:info).with(
          a_string_matching(/Category selected.*Found 1 providers/)
        )

        expect(Rails.logger).not_to have_received(:info).with(
          a_string_matching(/No providers found/)
        )
      end
    end
  end
end
