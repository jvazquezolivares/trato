# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhooks", type: :request do
  describe "GET /webhooks/whatsapp (verify)" do
    let(:verify_token) { "test_verify_token_123" }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("WHATSAPP_VERIFY_TOKEN").and_return(verify_token)
    end

    context "when verify token matches" do
      it "responds with the hub.challenge value" do
        get "/webhooks/whatsapp", params: {
          "hub.verify_token" => verify_token,
          "hub.challenge" => "challenge_abc_123",
          "hub.mode" => "subscribe"
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("challenge_abc_123")
      end
    end

    context "when verify token does not match" do
      it "responds with HTTP 403" do
        get "/webhooks/whatsapp", params: {
          "hub.verify_token" => "wrong_token",
          "hub.challenge" => "challenge_abc_123",
          "hub.mode" => "subscribe"
        }

        expect(response).to have_http_status(:forbidden)
        expect(response.body).to eq("Error")
      end
    end

    context "when verify token is missing" do
      it "responds with HTTP 403" do
        get "/webhooks/whatsapp", params: {
          "hub.challenge" => "challenge_abc_123"
        }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST /webhooks/whatsapp (receive)" do
    let(:provider_phone_number_id) { "111111111111" }
    let(:client_phone_number_id) { "222222222222" }

    let(:meta_payload) do
      {
        entry: [ {
          changes: [ {
            value: {
              metadata: { phone_number_id: "123456" },
              messages: [ {
                from: "5212211234567",
                text: { body: "Hola" },
                image: { url: "https://example.com/photo.jpg" }
              } ]
            }
          } ]
        } ]
      }
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("WHATSAPP_PROVIDER_PHONE_NUMBER_ID").and_return(provider_phone_number_id)
      allow(ENV).to receive(:[]).with("WHATSAPP_CLIENT_PHONE_NUMBER_ID").and_return(client_phone_number_id)

      # Prevent actual job execution — we only verify it gets enqueued
      allow(ProcessWhatsappMessageJob).to receive(:perform_later)

      # Stub the new jobs to prevent NameError until they are created in Task 7
      provider_job_class = Class.new do
        def self.perform_later(*_args); end
      end
      client_job_class = Class.new do
        def self.perform_later(*_args); end
      end

      stub_const("ProviderMessageJob", provider_job_class)
      stub_const("ClientMessageJob", client_job_class)
      allow(ProviderMessageJob).to receive(:perform_later)
      allow(ClientMessageJob).to receive(:perform_later)
    end

    it "always returns HTTP 200" do
      post "/webhooks/whatsapp", params: meta_payload, as: :json

      expect(response).to have_http_status(:ok)
    end

    context "when phone_number_id matches provider number" do
      let(:provider_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: provider_phone_number_id },
                messages: [ {
                  from: "5212211234567",
                  text: { body: "Hola desde provider" }
                } ]
              }
            } ]
          } ]
        }
      end

      it "enqueues ProviderMessageJob" do
        post "/webhooks/whatsapp", params: provider_payload, as: :json

        expect(ProviderMessageJob).to have_received(:perform_later).with(
          "5212211234567",
          "Hola desde provider",
          nil
        )
      end
    end

    context "when phone_number_id matches client number" do
      let(:client_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: client_phone_number_id },
                messages: [ {
                  from: "5212219876543",
                  text: { body: "Hola desde client" }
                } ]
              }
            } ]
          } ]
        }
      end

      it "enqueues ClientMessageJob" do
        post "/webhooks/whatsapp", params: client_payload, as: :json

        expect(ClientMessageJob).to have_received(:perform_later).with(
          "5212219876543",
          "Hola desde client",
          nil
        )
      end
    end

    context "when phone_number_id is unknown" do
      let(:unknown_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: "999999999999" },
                messages: [ {
                  from: "5212211111111",
                  text: { body: "Message from unknown number" }
                } ]
              }
            } ]
          } ]
        }
      end

      it "logs a warning with phone_number_id and sender details" do
        allow(Rails.logger).to receive(:warn)

        post "/webhooks/whatsapp", params: unknown_payload, as: :json

        expect(Rails.logger).to have_received(:warn).with(
          a_string_matching(/Unknown phone_number_id received: 999999999999/)
            .and(matching(/Sender: 5212211111111/))
            .and(matching(/Message preview: Message from unknown number/))
            .and(matching(/Timestamp:/))
        )
      end

      it "returns HTTP 200 without enqueuing any job" do
        post "/webhooks/whatsapp", params: unknown_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProviderMessageJob).not_to have_received(:perform_later)
        expect(ClientMessageJob).not_to have_received(:perform_later)
      end
    end

    context "when payload has no messages" do
      let(:empty_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: "123456" }
              }
            } ]
          } ]
        }
      end

      it "returns HTTP 200 without enqueuing a job" do
        post "/webhooks/whatsapp", params: empty_payload, as: :json

        expect(response).to have_http_status(:ok)
        expect(ProcessWhatsappMessageJob).not_to have_received(:perform_later)
      end
    end

    context "when payload is a text-only message (no image)" do
      let(:text_only_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: provider_phone_number_id },
                messages: [ {
                  from: "5212219876543",
                  text: { body: "a3f8c2d1" }
                } ]
              }
            } ]
          } ]
        }
      end

      it "enqueues job with nil media_url" do
        post "/webhooks/whatsapp", params: text_only_payload, as: :json

        expect(ProviderMessageJob).to have_received(:perform_later).with(
          "5212219876543",
          "a3f8c2d1",
          nil
        )
      end
    end

    context "when payload is an interactive List Message response" do
      let(:list_reply_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: provider_phone_number_id },
                messages: [ {
                  from: "5212211234567",
                  type: "interactive",
                  interactive: {
                    type: "list_reply",
                    list_reply: {
                      id: "income",
                      title: "Ver ingresos"
                    }
                  }
                } ]
              }
            } ]
          } ]
        }
      end

      it "extracts the selection ID and enqueues job with it as body" do
        post "/webhooks/whatsapp", params: list_reply_payload, as: :json

        expect(ProviderMessageJob).to have_received(:perform_later).with(
          "5212211234567",
          "income",
          nil
        )
      end
    end

    context "when payload is a star rating List Message response" do
      let(:rating_list_reply_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: client_phone_number_id },
                messages: [ {
                  from: "5212219876543",
                  type: "interactive",
                  interactive: {
                    type: "list_reply",
                    list_reply: {
                      id: "5",
                      title: "⭐⭐⭐⭐⭐ Excelente"
                    }
                  }
                } ]
              }
            } ]
          } ]
        }
      end

      it "extracts the rating selection ID and enqueues ClientMessageJob" do
        post "/webhooks/whatsapp", params: rating_list_reply_payload, as: :json

        expect(ClientMessageJob).to have_received(:perform_later).with(
          "5212219876543",
          "5",
          nil
        )
      end

      it "passes numeric string ID that can be processed by ReviewCollectionService" do
        post "/webhooks/whatsapp", params: rating_list_reply_payload, as: :json

        # Verify the body parameter is the numeric string "5"
        expect(ClientMessageJob).to have_received(:perform_later) do |from, body, media_url|
          expect(body).to eq("5")
          expect(body.to_i).to eq(5)
          expect(body.to_i.between?(1, 5)).to be(true)
        end
      end
    end

    context "when payload is an interactive Button Reply response" do
      let(:button_reply_payload) do
        {
          entry: [ {
            changes: [ {
              value: {
                metadata: { phone_number_id: client_phone_number_id },
                messages: [ {
                  from: "5212219876543",
                  type: "interactive",
                  interactive: {
                    type: "button_reply",
                    button_reply: {
                      id: "yes_confirm",
                      title: "Sí, confirmar"
                    }
                  }
                } ]
              }
            } ]
          } ]
        }
      end

      it "extracts the button ID and enqueues job with it as body" do
        post "/webhooks/whatsapp", params: button_reply_payload, as: :json

        expect(ClientMessageJob).to have_received(:perform_later).with(
          "5212219876543",
          "yes_confirm",
          nil
        )
      end
    end
  end
end
