# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhook Routing Integration", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:provider_phone_number_id) { "123456789" }
  let(:client_phone_number_id) { "987654321" }
  let(:sender_phone) { "5219999999999" }
  let(:message_body) { "Hola, necesito ayuda" }

  before do
    # Set environment variables for routing
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_PROVIDER_PHONE_NUMBER_ID").and_return(provider_phone_number_id)
    allow(ENV).to receive(:[]).with("WHATSAPP_CLIENT_PHONE_NUMBER_ID").and_return(client_phone_number_id)

    # Mock the job handlers to prevent actual processing
    allow(ProviderConversationHandler).to receive(:call).and_return(nil)
    allow(ClientAssistantOrchestrator).to receive(:call_search_mode).and_return(nil)

    # Clear any enqueued jobs before each test
    clear_enqueued_jobs
  end

  describe "POST /webhooks/whatsapp with provider phone_number_id" do
    context "when message is sent to provider number" do
      let(:webhook_payload) do
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
                        from: sender_phone,
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

      it "routes to ProviderMessageJob and processes through ProviderConversationHandler" do
        # Perform the webhook request
        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        # Verify HTTP response
        expect(response).to have_http_status(:ok)

        # Verify the job was enqueued
        expect(ProviderMessageJob).to have_been_enqueued.with(
          sender_phone,
          message_body,
          nil
        )

        # Execute the enqueued job
        perform_enqueued_jobs

        # Verify ProviderConversationHandler was called with correct parameters
        expect(ProviderConversationHandler).to have_received(:call).with(
          from: sender_phone,
          body: message_body,
          media_url: nil
        )
      end

      it "handles messages with media attachments" do
        media_url = "https://example.com/image.jpg"
        webhook_payload[:entry][0][:changes][0][:value][:messages][0][:type] = "image"
        webhook_payload[:entry][0][:changes][0][:value][:messages][0][:image] = { url: media_url }

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)

        expect(ProviderMessageJob).to have_been_enqueued.with(
          sender_phone,
          message_body,
          media_url
        )

        perform_enqueued_jobs

        expect(ProviderConversationHandler).to have_received(:call).with(
          from: sender_phone,
          body: message_body,
          media_url: media_url
        )
      end

      it "handles interactive List Message selections" do
        selected_option_id = "price_range_200_400"
        webhook_payload[:entry][0][:changes][0][:value][:messages][0] = {
          from: sender_phone,
          type: "interactive",
          interactive: {
            type: "list_reply",
            list_reply: {
              id: selected_option_id,
              title: "$200–400 MXN"
            }
          }
        }

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)

        expect(ProviderMessageJob).to have_been_enqueued.with(
          sender_phone,
          selected_option_id,
          nil
        )

        perform_enqueued_jobs

        expect(ProviderConversationHandler).to have_received(:call).with(
          from: sender_phone,
          body: selected_option_id,
          media_url: nil
        )
      end

      it "handles interactive Button Reply selections" do
        button_id = "confirm_appointment"
        webhook_payload[:entry][0][:changes][0][:value][:messages][0] = {
          from: sender_phone,
          type: "interactive",
          interactive: {
            type: "button_reply",
            button_reply: {
              id: button_id,
              title: "Confirmar"
            }
          }
        }

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)

        expect(ProviderMessageJob).to have_been_enqueued.with(
          sender_phone,
          button_id,
          nil
        )

        perform_enqueued_jobs

        expect(ProviderConversationHandler).to have_received(:call).with(
          from: sender_phone,
          body: button_id,
          media_url: nil
        )
      end
    end

    context "when message has no sender phone" do
      let(:webhook_payload) do
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

      it "returns 200 OK but does not enqueue any job" do
        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProviderMessageJob).not_to have_been_enqueued
        expect(ClientMessageJob).not_to have_been_enqueued
      end
    end

    context "when payload is malformed" do
      let(:webhook_payload) do
        {
          entry: []
        }
      end

      it "returns 200 OK without processing" do
        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProviderMessageJob).not_to have_been_enqueued
      end
    end
  end

  describe "POST /webhooks/whatsapp with unknown phone_number_id" do
    context "when message is sent to an unrecognized number" do
      let(:unknown_phone_number_id) { "111111111" }
      let(:webhook_payload) do
        {
          entry: [
            {
              changes: [
                {
                  value: {
                    metadata: {
                      phone_number_id: unknown_phone_number_id
                    },
                    messages: [
                      {
                        from: sender_phone,
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

      it "returns 200 OK without enqueuing any job" do
        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProviderMessageJob).not_to have_been_enqueued
        expect(ClientMessageJob).not_to have_been_enqueued
      end

      it "logs a warning with the unknown phone_number_id" do
        # Capture log output
        allow(Rails.logger).to receive(:warn)

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        expect(Rails.logger).to have_received(:warn).with(
          a_string_matching(/Unknown phone_number_id received: #{unknown_phone_number_id}/)
            .and(matching(/Sender: #{sender_phone}/))
            .and(matching(/Message preview: #{message_body}/))
        )
      end

      it "includes timestamp in the warning log" do
        allow(Rails.logger).to receive(:warn)
        freeze_time = Time.current

        travel_to(freeze_time) do
          post "/webhooks/whatsapp", params: webhook_payload, as: :json

          expect(Rails.logger).to have_received(:warn).with(
            a_string_matching(/Timestamp: #{freeze_time}/)
          )
        end
      end

      it "truncates long messages in the log preview" do
        long_message = "a" * 100
        webhook_payload[:entry][0][:changes][0][:value][:messages][0][:text][:body] = long_message

        allow(Rails.logger).to receive(:warn)

        post "/webhooks/whatsapp", params: webhook_payload, as: :json

        # Verify the message was truncated to 50 characters
        expect(Rails.logger).to have_received(:warn).with(
          a_string_matching(/Message preview: #{"a" * 47}\.\.\./)
        )
      end
    end
  end

  describe "end-to-end provider onboarding flow" do
    let(:new_provider_phone) { "5218111234567" }
    let(:provider_name) { "Miguel Hernández" }

    before do
      allow(WhatsAppService).to receive(:send_message).and_return(nil)
      allow(ProviderConversationHandler).to receive(:call).and_call_original
    end

    it "processes a new provider registration through the provider number" do
      # Step 1: New user sends initial message to provider number
      webhook_payload = {
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
                      from: new_provider_phone,
                      type: "text",
                      text: {
                        body: "Hola"
                      }
                    }
                  ]
                }
              }
            ]
          }
        ]
      }

      post "/webhooks/whatsapp", params: webhook_payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(ProviderMessageJob).to have_been_enqueued

      # Execute the job
      perform_enqueued_jobs

      # Verify ProviderConversationHandler was called
      expect(ProviderConversationHandler).to have_received(:call).with(
        from: new_provider_phone,
        body: "Hola",
        media_url: nil
      )

      # Verify a welcome message was sent (onboarding flow started)
      expect(WhatsAppService).to have_received(:send_message)
    end
  end
end
