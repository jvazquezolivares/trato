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

      # Step 3: Client sends this message from their phone to CLIENT NUMBER
      client_phone = "5219999999999"

      # Mock the ClientAssistantOrchestrator to verify it gets called
      allow(ClientAssistantOrchestrator).to receive(:call).and_return(nil)

      # Simulate ClientMessageJob processing the message (client number flow)
      ClientMessageJob.new.perform(client_phone, message_text, nil)

      # Verify it routes to ClientAssistantOrchestrator with the correct provider
      expect(ClientAssistantOrchestrator).to have_received(:call).with(
        provider: provider,
        from: client_phone,
        body: message_text
      )
    end

    it "extracts short_uuid from various natural message formats" do
      allow(ClientAssistantOrchestrator).to receive(:call).and_return(nil)
      allow(Provider).to receive(:find_by).and_call_original
      allow(Provider).to receive(:find_by).with(short_uuid: "a3f8c2d1").and_return(provider)
      client_phone = "5219999999999"

      natural_messages = [
        "Hola, me pasaron este contacto (a3f8c2d1)",
        "Buenos días, me dieron este número a3f8c2d1",
        "a3f8c2d1 - me recomendaron llamar",
        "Busco información, código: a3f8c2d1"
      ]

      natural_messages.each do |message|
        # Messages go through ClientMessageJob (client number)
        ClientMessageJob.new.perform(client_phone, message, nil)
      end

      # All messages should route to ClientAssistantOrchestrator
      expect(ClientAssistantOrchestrator).to have_received(:call).exactly(natural_messages.length).times
    end

    it "does not match invalid hex patterns and triggers search mode" do
      allow(ClientAssistantOrchestrator).to receive(:call_search_mode).and_return(nil)
      client_phone = "5219999999999"

      invalid_messages = [
        "Hola, mi código es abc123",  # Only 6 chars
        "Busco fontanero 123456789",  # 9 chars, too long
        "Contacto: gggggggg",          # Not valid hex (g is not hex)
        "Hola"                         # No code at all
      ]

      invalid_messages.each do |message|
        # Messages without valid short_uuid go to search mode (C2A flow)
        ClientMessageJob.new.perform(client_phone, message, nil)
      end

      # Should trigger search mode for all invalid messages
      expect(ClientAssistantOrchestrator).to have_received(:call_search_mode).exactly(invalid_messages.length).times
    end
  end
end
