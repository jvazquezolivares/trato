# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Assistant Link Routing Integration", type: :integration do
  let(:redis_mock) { instance_double(Redis) }
  let(:provider) { create(:provider, short_uuid: "a3f8c2d1") }

  before do
    stub_const("REDIS", redis_mock)
    allow(WhatsAppService).to receive(:send_message).and_return(nil)
    allow(redis_mock).to receive(:get).and_return(nil)
  end

  describe "end-to-end flow" do
    it "generates a personalized link and routes correctly when client uses it" do
      # Step 1: Provider gets their assistant link
      link = provider.assistant_whatsapp_link

      # Verify the link has the personalized format with provider name
      expect(link).to include("Env")
      expect(link).to include(provider.name.split.first) # First name at minimum
      expect(link).to include("a3f8c2d1")
      expect(link).to match(/%28a3f8c2d1%29/) # URL-encoded parentheses

      # Step 2: Decode the link to get what the client would send
      uri = URI.parse(link)
      params = URI.decode_www_form(uri.query)
      message_text = params.find { |k, _v| k == "text" }&.last

      expect(message_text).to include("Envía este mensaje para contactar al asistente de")
      expect(message_text).to include(provider.name)
      expect(message_text).to include("(a3f8c2d1)")

      # Step 3: Client sends this message from their phone
      client_phone = "5219999999999"

      # Mock the ClientAssistant to verify it gets called
      allow(ClientAssistant).to receive(:call).and_return(nil)

      # Simulate the webhook receiving the message
      ConversationHandler.call(from: client_phone, body: message_text, media_url: nil)

      # Verify it routes to ClientAssistant with the correct provider
      expect(ClientAssistant).to have_received(:call).with(
        provider: provider,
        from: client_phone,
        body: message_text
      )
    end

    it "extracts short_uuid from various natural message formats" do
      allow(ClientAssistant).to receive(:call).and_return(nil)
      allow(Provider).to receive(:find_by).and_call_original
      allow(Provider).to receive(:find_by).with(phone: anything).and_return(nil)
      allow(Provider).to receive(:find_by).with(short_uuid: "a3f8c2d1").and_return(provider)
      client_phone = "5219999999999"

      natural_messages = [
        "Hola, me pasaron este contacto (a3f8c2d1)",
        "Buenos días, me dieron este número a3f8c2d1",
        "a3f8c2d1 - me recomendaron llamar",
        "Busco información, código: a3f8c2d1"
      ]

      natural_messages.each do |message|
        ConversationHandler.call(from: client_phone, body: message, media_url: nil)
      end

      # All messages should route to ClientAssistant
      expect(ClientAssistant).to have_received(:call).exactly(natural_messages.length).times
    end

    it "does not match invalid hex patterns" do
      allow(ClientAssistant).to receive(:call).and_return(nil)
      allow(redis_mock).to receive(:setex).and_return("OK")
      client_phone = "5219999999999"

      invalid_messages = [
        "Hola, mi código es abc123",  # Only 6 chars
        "Busco fontanero 12345678",   # Numbers only, not hex
        "Contacto: gggggggg",          # Not valid hex
        "Hola"                         # No code at all
      ]

      invalid_messages.each do |message|
        ConversationHandler.call(from: client_phone, body: message, media_url: nil)
      end

      # None should route to ClientAssistant
      expect(ClientAssistant).not_to have_received(:call)
      # Should send welcome message instead
      expect(WhatsAppService).to have_received(:send_message).exactly(invalid_messages.length).times
    end
  end
end
