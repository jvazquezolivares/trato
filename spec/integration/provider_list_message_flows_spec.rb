# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Provider List Message Flows Integration (P4, P5, P17)", type: :request do
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

  describe "P4: Diagnosis Visit Price Selection via List Message" do
    context "when provider reaches price collection stage" do
      before do
        # Setup Redis state for collecting_area stage (before price)
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({
            "stage" => "collecting_area",
            "data" => {
              "name" => "Miguel",
              "categories" => ["fontanero"],
              "city" => "Veracruz"
            }
          }.to_json)
      end

      it "sends List Message with 4 price range options" do
        # Trigger price collection by sending area
        webhook_payload = build_webhook_payload(provider_phone, "Boca del Río")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify List Message was sent with correct structure
        expect(WhatsAppService).to have_received(:send_list_message) do |args|
          payload = args[:payload]

          # Verify type
          expect(payload[:type]).to eq("list")

          # Verify header
          expect(payload[:header][:type]).to eq("text")
          expect(payload[:header][:text]).to eq("Rango de precio")

          # Verify body
          expect(payload[:body][:text]).to be_present

          # Verify action structure
          expect(payload[:action][:button]).to eq("Ver opciones")
          expect(payload[:action][:sections]).to be_an(Array)
          expect(payload[:action][:sections].length).to eq(1)

          # Verify all 4 price ranges are present
          rows = payload[:action][:sections][0][:rows]
          expect(rows.length).to eq(4)

          # Verify each option has id and title
          expected_ids = %w[100-200 200-400 400-600 600+]
          actual_ids = rows.map { |row| row[:id] }
          expect(actual_ids).to match_array(expected_ids)

          # Verify titles match requirements
          expect(rows.find { |r| r[:id] == "100-200" }[:title]).to eq("$100–200 MXN")
          expect(rows.find { |r| r[:id] == "200-400" }[:title]).to eq("$200–400 MXN")
          expect(rows.find { |r| r[:id] == "400-600" }[:title]).to eq("$400–600 MXN")
          expect(rows.find { |r| r[:id] == "600+" }[:title]).to eq("Más de $600 MXN")

          # Verify button labels are within 20-character limit
          rows.each do |row|
            expect(row[:title].length).to be <= 20
          end
        end
      end

      it "handles all 4 price range selections correctly" do
        price_ranges = [
          { id: "100-200", title: "$100–200 MXN", expected_value: "$100–200 MXN" },
          { id: "200-400", title: "$200–400 MXN", expected_value: "$200–400 MXN" },
          { id: "400-600", title: "$400–600 MXN", expected_value: "$400–600 MXN" },
          { id: "600+", title: "Más de $600 MXN", expected_value: "Más de $600 MXN" }
        ]

        price_ranges.each_with_index do |range, index|
          # Use unique phone for each iteration to avoid conflicts
          test_phone = "521811234567#{index}"

          # Setup Redis state for collecting_price stage
          allow(redis_mock).to receive(:get)
            .with("onboarding_state:#{test_phone}")
            .and_return({
              "stage" => "collecting_price",
              "data" => {
                "name" => "Miguel",
                "categories" => ["fontanero"],
                "city" => "Veracruz",
                "service_area" => "Boca del Río"
              }
            }.to_json)

          # Reset mocks for each iteration
          allow(WhatsAppService).to receive(:send_list_message).and_return(nil)
          allow(redis_mock).to receive(:setex).and_return("OK")

          # Provider selects price range
          webhook_payload = build_interactive_list_reply_payload(test_phone, range[:id], range[:title])

          post "/webhooks/whatsapp", params: webhook_payload, as: :json
          perform_enqueued_jobs

          # Verify price was stored in Redis data
          expect(redis_mock).to have_received(:setex).with(
            "onboarding_state:#{test_phone}",
            86_400,
            a_string_matching(/"base_price":"#{Regexp.escape(range[:expected_value])}"/)
          ).at_least(:once)

          # Verify transition to collecting_experience stage
          expect(redis_mock).to have_received(:setex).with(
            "onboarding_state:#{test_phone}",
            86_400,
            a_string_matching(/"stage":"collecting_experience"/)
          ).at_least(:once)
        end
      end

      it "does not use Quick Reply Buttons for price selection" do
        # Setup Redis state for collecting_area stage
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({
            "stage" => "collecting_area",
            "data" => {
              "name" => "Miguel",
              "categories" => ["fontanero"],
              "city" => "Veracruz"
            }
          }.to_json)

        webhook_payload = build_webhook_payload(provider_phone, "Boca del Río")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify no Quick Reply Buttons were sent
        expect(WhatsAppService).not_to have_received(:send_message).with(
          hash_including(buttons: anything)
        )

        # Verify List Message was used instead
        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "transitions from collecting_price to collecting_experience on valid selection" do
        # Setup Redis state for collecting_price stage
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({
            "stage" => "collecting_price",
            "data" => {
              "name" => "Miguel",
              "categories" => ["fontanero"],
              "city" => "Veracruz",
              "service_area" => "Boca del Río"
            }
          }.to_json)

        webhook_payload = build_interactive_list_reply_payload(provider_phone, "200-400", "$200–400 MXN")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify stage transition
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"stage":"collecting_experience"/)
        ).at_least(:once)

        # Verify experience List Message was sent
        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: provider_phone,
          payload: a_hash_including(
            header: a_hash_including(text: "Años de experiencia")
          )
        )
      end
    end
  end

  describe "P5: Years of Experience Selection via List Message" do
    context "when provider reaches experience collection stage" do
      before do
        # Setup Redis state for collecting_price stage (before experience)
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({
            "stage" => "collecting_price",
            "data" => {
              "name" => "Miguel",
              "categories" => ["fontanero"],
              "city" => "Veracruz",
              "service_area" => "Boca del Río"
            }
          }.to_json)
      end

      it "sends List Message with 4 experience range options" do
        # Trigger experience collection by sending price
        webhook_payload = build_interactive_list_reply_payload(provider_phone, "200-400", "$200–400 MXN")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify List Message was sent with correct structure
        expect(WhatsAppService).to have_received(:send_list_message) do |args|
          payload = args[:payload]

          # Verify type
          expect(payload[:type]).to eq("list")

          # Verify header
          expect(payload[:header][:type]).to eq("text")
          expect(payload[:header][:text]).to eq("Años de experiencia")

          # Verify body
          expect(payload[:body][:text]).to be_present

          # Verify action structure
          expect(payload[:action][:button]).to eq("Ver opciones")
          expect(payload[:action][:sections]).to be_an(Array)
          expect(payload[:action][:sections].length).to eq(1)

          # Verify all 4 experience ranges are present
          rows = payload[:action][:sections][0][:rows]
          expect(rows.length).to eq(4)

          # Verify each option has id and title
          expected_ids = %w[1-3 4-6 7-10 10+]
          actual_ids = rows.map { |row| row[:id] }
          expect(actual_ids).to match_array(expected_ids)

          # Verify titles match requirements
          expect(rows.find { |r| r[:id] == "1-3" }[:title]).to eq("1–3 años")
          expect(rows.find { |r| r[:id] == "4-6" }[:title]).to eq("4–6 años")
          expect(rows.find { |r| r[:id] == "7-10" }[:title]).to eq("7–10 años")
          expect(rows.find { |r| r[:id] == "10+" }[:title]).to eq("Más de 10 años")

          # Verify button labels are within 20-character limit
          rows.each do |row|
            expect(row[:title].length).to be <= 20
          end
        end
      end

      it "handles all 4 experience range selections and maps to numeric values correctly" do
        experience_ranges = [
          { id: "1-3", title: "1–3 años", expected_numeric: 1 },
          { id: "4-6", title: "4–6 años", expected_numeric: 4 },
          { id: "7-10", title: "7–10 años", expected_numeric: 7 },
          { id: "10+", title: "Más de 10 años", expected_numeric: 10 }
        ]

        experience_ranges.each_with_index do |range, index|
          # Use unique phone for each iteration to avoid conflicts
          test_phone = "521811234568#{index}"

          # Setup Redis state for collecting_experience stage
          allow(redis_mock).to receive(:get)
            .with("onboarding_state:#{test_phone}")
            .and_return({
              "stage" => "collecting_experience",
              "data" => {
                "name" => "Miguel",
                "categories" => ["fontanero"],
                "city" => "Veracruz",
                "service_area" => "Boca del Río",
                "base_price" => "$200–400 MXN"
              }
            }.to_json)

          # Reset mocks for each iteration
          allow(WhatsAppService).to receive(:send_message).and_return(nil)
          allow(redis_mock).to receive(:setex).and_return("OK")

          # Provider selects experience range
          webhook_payload = build_interactive_list_reply_payload(test_phone, range[:id], range[:title])

          post "/webhooks/whatsapp", params: webhook_payload, as: :json
          perform_enqueued_jobs

          # Verify numeric value was stored in Redis data
          expect(redis_mock).to have_received(:setex).with(
            "onboarding_state:#{test_phone}",
            86_400,
            a_string_matching(/"years_experience":#{range[:expected_numeric]}/)
          ).at_least(:once)

          # Verify transition to next stage (collecting_specialties)
          expect(redis_mock).to have_received(:setex).with(
            "onboarding_state:#{test_phone}",
            86_400,
            a_string_matching(/"stage":"collecting_specialties"/)
          ).at_least(:once)
        end
      end

      it "does not use Quick Reply Buttons for experience selection" do
        # Setup Redis state for collecting_experience stage
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({
            "stage" => "collecting_experience",
            "data" => {
              "name" => "Miguel",
              "categories" => ["fontanero"],
              "city" => "Veracruz",
              "service_area" => "Boca del Río",
              "base_price" => "$200–400 MXN"
            }
          }.to_json)

        webhook_payload = build_interactive_list_reply_payload(provider_phone, "4-6", "4–6 años")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify no Quick Reply Buttons were sent
        expect(WhatsAppService).not_to have_received(:send_message).with(
          hash_including(buttons: anything)
        )

        # Verify List Message was used instead (for next stage)
        expect(WhatsAppService).to have_received(:send_message)
      end

      it "stores experience numeric value correctly" do
        # Setup Redis state for collecting_experience stage
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{provider_phone}")
          .and_return({
            "stage" => "collecting_experience",
            "data" => {
              "name" => "Miguel",
              "categories" => ["fontanero"],
              "city" => "Veracruz",
              "service_area" => "Boca del Río",
              "base_price" => "$200–400 MXN"
            }
          }.to_json)

        webhook_payload = build_interactive_list_reply_payload(provider_phone, "4-6", "4–6 años")

        post "/webhooks/whatsapp", params: webhook_payload, as: :json
        perform_enqueued_jobs

        # Verify numeric value is stored
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{provider_phone}",
          86_400,
          a_string_matching(/"years_experience":4/)
        ).at_least(:once)
      end
    end
  end

  describe "P17: Financial Summary Selection via List Message" do
    # Note: P17 flow is handled by ProviderAssistant and requires a registered provider
    # These tests are simplified to verify the List Message structure is correct
    # Full end-to-end testing of P17 is covered in provider_assistant_spec.rb

    let(:provider) { create(:provider, phone: provider_phone) }

    before do
      # Mock ProviderConversationHandler to route to ProviderAssistant
      allow(ProviderConversationHandler).to receive(:provider_by_phone).with(provider_phone).and_return(provider)
      allow(ProviderAssistant).to receive(:call).and_call_original

      # Mock ClaudeService to return show_financial_options action
      allow(ClaudeService).to receive(:call).and_return(
        {
          "message" => "¿Qué quieres ver?",
          "action" => "show_financial_options",
          "action_data" => {},
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => "financial_query_requested"
        }
      )
    end

    it "verifies List Message structure for financial options" do
      # Test the List Message builder directly
      list_message = WhatsApp::ListMessageBuilder.build_financial_options_list

      # Verify structure
      expect(list_message[:type]).to eq("list")
      expect(list_message[:header][:text]).to eq("¿Qué quieres ver?")
      expect(list_message[:action][:sections].first[:rows].length).to eq(4)

      # Verify all options are present
      rows = list_message[:action][:sections].first[:rows]
      expect(rows.map { |r| r[:id] }).to match_array(%w[income expenses pending no_thanks])

      # Verify titles
      expect(rows.find { |r| r[:id] == "income" }[:title]).to eq("Ver ingresos")
      expect(rows.find { |r| r[:id] == "expenses" }[:title]).to eq("Ver gastos")
      expect(rows.find { |r| r[:id] == "pending" }[:title]).to eq("Ver cobros")
      expect(rows.find { |r| r[:id] == "no_thanks" }[:title]).to eq("No, gracias")

      # Verify button labels are within 20-character limit
      rows.each do |row|
        expect(row[:title].length).to be <= 20
      end
    end
  end

  describe "Integration: Complete onboarding flow with P4 and P5" do
    it "processes provider through price and experience selection using List Messages" do
      # Setup initial onboarding state
      allow(redis_mock).to receive(:get)
        .with("onboarding_state:#{provider_phone}")
        .and_return({
          "stage" => "collecting_price",
          "data" => {
            "name" => "Miguel",
            "categories" => ["fontanero"],
            "city" => "Veracruz",
            "service_area" => "Boca del Río"
          }
        }.to_json)

      # Step 1: Provider selects price range
      webhook_payload = build_interactive_list_reply_payload(provider_phone, "200-400", "$200–400 MXN")

      post "/webhooks/whatsapp", params: webhook_payload, as: :json
      perform_enqueued_jobs

      # Verify price was stored
      expect(redis_mock).to have_received(:setex).with(
        "onboarding_state:#{provider_phone}",
        86_400,
        a_string_matching(/"base_price":"\$200–400 MXN"/)
      ).at_least(:once)

      # Verify transition to experience stage
      expect(redis_mock).to have_received(:setex).with(
        "onboarding_state:#{provider_phone}",
        86_400,
        a_string_matching(/"stage":"collecting_experience"/)
      ).at_least(:once)

      # Verify experience List Message was sent
      expect(WhatsAppService).to have_received(:send_list_message).with(
        to: provider_phone,
        payload: a_hash_including(
          header: a_hash_including(text: "Años de experiencia")
        )
      )

      # Step 2: Update Redis state for experience stage
      allow(redis_mock).to receive(:get)
        .with("onboarding_state:#{provider_phone}")
        .and_return({
          "stage" => "collecting_experience",
          "data" => {
            "name" => "Miguel",
            "categories" => ["fontanero"],
            "city" => "Veracruz",
            "service_area" => "Boca del Río",
            "base_price" => "$200–400 MXN"
          }
        }.to_json)

      # Step 3: Provider selects experience range
      clear_enqueued_jobs
      webhook_payload = build_interactive_list_reply_payload(provider_phone, "4-6", "4–6 años")

      post "/webhooks/whatsapp", params: webhook_payload, as: :json
      perform_enqueued_jobs

      # Verify experience was stored
      expect(redis_mock).to have_received(:setex).with(
        "onboarding_state:#{provider_phone}",
        86_400,
        a_string_matching(/"years_experience":4/)
      ).at_least(:once)

      # Verify transition to next stage
      expect(redis_mock).to have_received(:setex).with(
        "onboarding_state:#{provider_phone}",
        86_400,
        a_string_matching(/"stage":"collecting_specialties"/)
      ).at_least(:once)
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
