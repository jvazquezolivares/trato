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
      # Prevent actual job execution — we only verify it gets enqueued
      allow(ProcessWhatsappMessageJob).to receive(:perform_later)
    end

    it "always returns HTTP 200" do
      post "/webhooks/whatsapp", params: meta_payload, as: :json

      expect(response).to have_http_status(:ok)
    end

    it "enqueues ProcessWhatsappMessageJob with extracted message data" do
      post "/webhooks/whatsapp", params: meta_payload, as: :json

      expect(ProcessWhatsappMessageJob).to have_received(:perform_later).with(
        "5212211234567",
        "Hola",
        "https://example.com/photo.jpg"
      )
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
                metadata: { phone_number_id: "123456" },
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

        expect(ProcessWhatsappMessageJob).to have_received(:perform_later).with(
          "5212219876543",
          "a3f8c2d1",
          nil
        )
      end
    end
  end
end
