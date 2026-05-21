# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Provider Decline Flow Integration (P1B)", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:provider_phone_number_id) { "123456789" }
  let(:provider_phone) { "5218111234567" }
  let(:redis_mock) { instance_double(Redis) }

  before do
    # Set environment variables for routing
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_PROVIDER_PHONE_NUMBER_ID").and_return(provider_phone_number_id)

    # Mock Redis
    stub_const("REDIS", redis_mock)
    allow(redis_mock).to receive(:get).and_return(nil)
    allow(redis_mock).to receive(:setex).and_return("OK")
    allow(redis_mock).to receive(:del).and_return(1)

    # Mock WhatsApp service
    allow(WhatsAppService).to receive(:send_message).and_return(nil)
    allow(WhatsAppService).to receive(:send_list_message).and_return(nil)

    # Clear any enqueued jobs before each test
    clear_enqueued_jobs
  end

  describe "complete P1B decline flow end-to-end" do
    context "when provider declines registration during onboarding" do
      it "collects decline reason and closes conversation gracefully" do
        # Step 1: Provider sends initial message to provider number
        webhook_payload = build_webhook_payload(provider_phone, "Hola")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProviderMessageJob).to have_been_enqueued

        # Execute the job - this should trigger welcome message
        perform_enqueued_jobs

        # Verify welcome message was sent
        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider_phone,
          message: a_string_matching(/Trato/)
        )

        # Step 2: Simulate Redis state after welcome message
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({ "stage" => "onboarding_welcome", "data" => {} }.to_json)

        # Step 3: Provider responds with decline message
        clear_enqueued_jobs
        webhook_payload = build_webhook_payload(provider_phone, "Mejor después")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProviderMessageJob).to have_been_enqueued

        # Execute the job - this should trigger decline reasons List Message
        perform_enqueued_jobs

        # Verify decline reasons List Message was sent
        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: provider_phone,
          payload: a_hash_including(
            type: "list",
            header: a_hash_including(text: "¿Por qué no por ahora?")
          )
        )

        # Verify stage transition to collecting_decline_reason
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"stage":"collecting_decline_reason"/)
        )

        # Step 4: Simulate Redis state after decline reasons sent
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({ "stage" => "collecting_decline_reason", "data" => {} }.to_json)

        # Step 5: Provider selects a decline reason from List Message
        clear_enqueued_jobs
        webhook_payload = build_interactive_list_reply_payload(provider_phone, "busy", "Estoy muy ocupado")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProviderMessageJob).to have_been_enqueued

        # Execute the job - this should store reason and send closing message
        perform_enqueued_jobs

        # Verify decline reason was stored in database
        expect(OnboardingDecline.count).to eq(1)
        decline = OnboardingDecline.last
        expect(decline.phone).to eq(provider_phone)
        expect(decline.reason).to eq("busy")
        expect(decline.context["stage"]).to eq("onboarding")

        # Verify warm closing message was sent
        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider_phone,
          message: "¡Gracias por contarme! 😊 Cuando quieras crear tu cuenta, escríbeme aquí y con gusto te ayudo. ¡Que te vaya muy bien! — Elisa"
        )

        # Verify conversation stage was set to closed
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"stage":"closed"/)
        )
      end

      it "handles all 6 decline reason options correctly" do
        decline_reasons = [
          { id: "busy", title: "Estoy muy ocupado ahorita" },
          { id: "dont_understand", title: "No entiendo bien qué es Trato" },
          { id: "not_worth_it", title: "No sé si vale la pena" },
          { id: "uncomfortable_whatsapp", title: "No me siento cómodo con WhatsApp" },
          { id: "enough_clients", title: "Ya tengo suficientes clientes" },
          { id: "other", title: "Otro motivo" }
        ]

        decline_reasons.each_with_index do |reason, index|
          # Use unique phone for each iteration to avoid conflicts
          test_phone = "521811234567#{index}"

          # Setup Redis state for collecting_decline_reason
          allow(redis_mock).to receive(:get)
            .with("onboarding_state:#{test_phone}")
            .and_return({ "stage" => "collecting_decline_reason", "data" => {} }.to_json)

          # Provider selects decline reason
          webhook_payload = build_interactive_list_reply_payload(test_phone, reason[:id], reason[:title])

          post "/webhooks/whatsapp", params: webhook_payload, as: :json

          expect(response).to have_http_status(:ok)

          # Execute the job
          perform_enqueued_jobs

          # Verify decline reason was stored
          decline = OnboardingDecline.find_by(phone: test_phone)
          expect(decline).not_to be_nil
          expect(decline.reason).to eq(reason[:id])

          # Verify closing message was sent
          expect(WhatsAppService).to have_received(:send_message).with(
            to: test_phone,
            message: "¡Gracias por contarme! 😊 Cuando quieras crear tu cuenta, escríbeme aquí y con gusto te ayudo. ¡Que te vaya muy bien! — Elisa"
          )
        end
      end

      it "handles various decline message variations" do
        decline_variations = [
          "Mejor después",
          "no",
          "ahora no",
          "más tarde",
          "No gracias",
          "Mejor otro día"
        ]

        decline_variations.each do |variation|
          # Setup Redis state for onboarding_welcome
          allow(redis_mock).to receive(:get)
            .with("onboarding_state:#{provider_phone}")
            .and_return({ "stage" => "onboarding_welcome", "data" => {} }.to_json)

          # Reset mocks for each iteration
          allow(WhatsAppService).to receive(:send_list_message).and_return(nil)
          allow(redis_mock).to receive(:setex).and_return("OK")

          # Provider sends decline message
          webhook_payload = build_webhook_payload(provider_phone, variation)

          post "/webhooks/whatsapp", params: webhook_payload, as: :json

          expect(response).to have_http_status(:ok)

          # Execute the job
          perform_enqueued_jobs

          # Verify decline reasons List Message was sent for each variation
          # Use at_least(:once) since the mock is reset each iteration
          expect(WhatsAppService).to have_received(:send_list_message).with(
            to: provider_phone,
            payload: a_hash_including(
              type: "list",
              header: a_hash_including(text: "¿Por qué no por ahora?")
            )
          ).at_least(:once)
        end
      end
    end

    context "when provider provides blank response during decline reason collection" do
      it "prompts to select from list without closing conversation" do
        # Setup Redis state for collecting_decline_reason
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({ "stage" => "collecting_decline_reason", "data" => {} }.to_json)

        # Provider sends blank message
        webhook_payload = build_webhook_payload(provider_phone, "")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)

        # Execute the job
        perform_enqueued_jobs

        # Verify prompt message was sent
        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider_phone,
          message: "Por favor selecciona una razón de la lista."
        )

        # Verify no OnboardingDecline record was created
        expect(OnboardingDecline.count).to eq(0)

        # Verify conversation was NOT closed
        expect(redis_mock).not_to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"stage":"closed"/)
        )
      end
    end

    context "when testing complete flow with timestamp" do
      it "stores decline timestamp in ISO8601 format" do
        freeze_time = Time.current

        travel_to(freeze_time) do
          # Setup Redis state for collecting_decline_reason
          allow(redis_mock).to receive(:get)
            .with("onboarding_state:#{provider_phone}")
            .and_return({ "stage" => "collecting_decline_reason", "data" => {} }.to_json)

          # Provider selects decline reason
          webhook_payload = build_interactive_list_reply_payload(provider_phone, "busy", "Estoy muy ocupado")

          post "/webhooks/whatsapp", params: webhook_payload, as: :json

          expect(response).to have_http_status(:ok)

          # Execute the job
          perform_enqueued_jobs

          # Verify timestamp is stored correctly
          decline = OnboardingDecline.last
          expect(decline.context["declined_at"]).to eq(freeze_time.iso8601)
        end
      end
    end

    context "when testing List Message payload structure" do
      it "sends List Message with correct structure and all 6 options" do
        # Setup Redis state for onboarding_welcome
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({ "stage" => "onboarding_welcome", "data" => {} }.to_json)

        # Provider sends decline message
        webhook_payload = build_webhook_payload(provider_phone, "Mejor después")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        # Execute the job
        perform_enqueued_jobs

        # Verify List Message structure
        expect(WhatsAppService).to have_received(:send_list_message) do |args|
          payload = args[:payload]

          # Verify type
          expect(payload[:type]).to eq("list")

          # Verify header
          expect(payload[:header][:type]).to eq("text")
          expect(payload[:header][:text]).to eq("¿Por qué no por ahora?")

          # Verify body
          expect(payload[:body][:text]).to be_present

          # Verify action structure
          expect(payload[:action][:button]).to eq("Ver opciones")
          expect(payload[:action][:sections]).to be_an(Array)
          expect(payload[:action][:sections].length).to eq(1)

          # Verify all 6 decline reasons are present
          rows = payload[:action][:sections][0][:rows]
          expect(rows.length).to eq(6)

          # Verify each option has id and title
          expected_ids = %w[busy dont_understand not_worth_it uncomfortable_whatsapp enough_clients other]
          actual_ids = rows.map { |row| row[:id] }
          expect(actual_ids).to match_array(expected_ids)

          rows.each do |row|
            expect(row[:id]).to be_present
            expect(row[:title]).to be_present
            expect(row[:title].length).to be <= 24 # WhatsApp limit
          end
        end
      end
    end

    context "when testing Redis state transitions" do
      it "transitions through correct stages: onboarding_welcome → collecting_decline_reason → closed" do
        # Stage 1: onboarding_welcome
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({ "stage" => "onboarding_welcome", "data" => {} }.to_json)

        webhook_payload = build_webhook_payload(provider_phone, "Mejor después")
        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify transition to collecting_decline_reason
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"stage":"collecting_decline_reason"/)
        )

        # Stage 2: collecting_decline_reason
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({ "stage" => "collecting_decline_reason", "data" => {} }.to_json)

        webhook_payload = build_interactive_list_reply_payload(provider_phone, "busy", "Estoy muy ocupado")
        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify transition to closed
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"stage":"closed"/)
        )

        # Verify decline_reason is stored in Redis data before closing
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"decline_reason":"busy"/)
        ).at_least(:once)
      end
    end

    context "when testing message content and tone" do
      it "sends warm closing message with correct emoji and signature" do
        # Setup Redis state for collecting_decline_reason
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({ "stage" => "collecting_decline_reason", "data" => {} }.to_json)

        # Provider selects decline reason
        webhook_payload = build_interactive_list_reply_payload(provider_phone, "busy", "Estoy muy ocupado")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify exact message content
        expected_message = "¡Gracias por contarme! 😊 Cuando quieras crear tu cuenta, escríbeme aquí y con gusto te ayudo. ¡Que te vaya muy bien! — Elisa"

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider_phone,
          message: expected_message
        )

        # Verify message contains required elements
        expect(expected_message).to include("😊") # Emoji
        expect(expected_message).to include("— Elisa") # Signature
        expect(expected_message).to include("Gracias por contarme") # Gratitude
        expect(expected_message).to include("Cuando quieras crear tu cuenta") # Re-engagement invitation
      end
    end
  end

  # Helper methods to build webhook payloads
  private

  def build_webhook_payload(from_phone, message_body)
    {
      entry: [
        {
          changes: [
            {
              value: {
                metadata: {
                  phone_number_id: provider_phone_number_id
                },
                messages: [
                  {
                    from: from_phone,
                    type: "text",
                    text: {
                      body: message_body
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }
  end

  def build_interactive_list_reply_payload(from_phone, option_id, option_title)
    {
      entry: [
        {
          changes: [
            {
              value: {
                metadata: {
                  phone_number_id: provider_phone_number_id
                },
                messages: [
                  {
                    from: from_phone,
                    type: "interactive",
                    interactive: {
                      type: "list_reply",
                      list_reply: {
                        id: option_id,
                        title: option_title
                      }
                    }
                  }
                ]
              }
            }
          ]
        }
      ]
    }
  end
end
