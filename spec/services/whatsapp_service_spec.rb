# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe WhatsAppService, type: :service do
  let(:phone_number_id) { "9988776655" }
  let(:access_token) { "test_access_token_abc" }
  let(:api_url) { "https://graph.facebook.com/v19.0/#{phone_number_id}/messages" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_PHONE_NUMBER_ID").and_return(phone_number_id)
    allow(ENV).to receive(:[]).with("WHATSAPP_ACCESS_TOKEN").and_return(access_token)
  end

  describe ".send_message" do
    it "sends a text message to the Meta Cloud API" do
      stub = stub_request(:post, api_url)
        .with(
          headers: {
            "Authorization" => "Bearer #{access_token}",
            "Content-Type" => "application/json"
          },
          body: {
            messaging_product: "whatsapp",
            to: "5212211234567",
            type: "text",
            text: { body: "Hola Miguel" }
          }.to_json
        )
        .to_return(status: 200, body: { messages: [ { id: "wamid.123" } ] }.to_json)

      described_class.send_message(to: "5212211234567", message: "Hola Miguel")

      expect(stub).to have_been_requested
    end

    it "logs an error when the API returns a non-success status" do
      stub_request(:post, api_url).to_return(status: 401, body: "Unauthorized")

      allow(Rails.logger).to receive(:error)

      described_class.send_message(to: "5212211234567", message: "Test")

      expect(Rails.logger).to have_received(:error).with(/Failed to send message/)
    end
  end

  describe ".send_multipart" do
    let(:messages) { [ "Parte 1", "Parte 2", "Parte 3" ] }

    before do
      stub_request(:post, api_url).to_return(status: 200, body: "{}".to_json)
      # Stub sleep to avoid actual delays in tests
      allow(described_class).to receive(:sleep)
    end

    it "sends each message in the array" do
      described_class.send_multipart(to: "5212211234567", messages: messages)

      expect(WebMock).to have_requested(:post, api_url).times(3)
    end

    it "pauses 1.5 seconds between messages but not after the last one" do
      described_class.send_multipart(to: "5212211234567", messages: messages)

      expect(described_class).to have_received(:sleep).with(1.5).twice
    end

    it "does not sleep when there is only one message" do
      described_class.send_multipart(to: "5212211234567", messages: [ "Solo uno" ])

      expect(described_class).not_to have_received(:sleep)
    end
  end

  describe ".send_list_message" do
    let(:list_payload) do
      {
        type: "list",
        header: {
          type: "text",
          text: "¿Por qué no por ahora?"
        },
        body: {
          text: "Me ayudaría saber qué te detiene"
        },
        action: {
          button: "Ver opciones",
          sections: [
            {
              title: "Razón",
              rows: [
                { id: "busy", title: "Estoy muy ocupado" },
                { id: "other", title: "Otro motivo" }
              ]
            }
          ]
        }
      }
    end

    it "sends an interactive List Message to the Meta Cloud API" do
      stub = stub_request(:post, api_url)
        .with(
          headers: {
            "Authorization" => "Bearer #{access_token}",
            "Content-Type" => "application/json"
          },
          body: {
            messaging_product: "whatsapp",
            to: "5212211234567",
            type: "interactive",
            interactive: list_payload
          }.to_json
        )
        .to_return(status: 200, body: { messages: [ { id: "wamid.456" } ] }.to_json)

      described_class.send_list_message(to: "5212211234567", payload: list_payload)

      expect(stub).to have_been_requested
    end

    it "logs an error when the API returns a non-success status" do
      stub_request(:post, api_url).to_return(status: 400, body: "Bad Request")

      allow(Rails.logger).to receive(:error)

      described_class.send_list_message(to: "5212211234567", payload: list_payload)

      expect(Rails.logger).to have_received(:error).with(/Failed to send list message/)
    end
  end
end
