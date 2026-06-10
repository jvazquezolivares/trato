# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProviderConversationHandler, type: :service do
  let(:redis_mock) { instance_double(Redis) }

  before do
    stub_const("REDIS", redis_mock)
    allow(WhatsAppService).to receive(:send_message).and_return(nil)
    allow(ProviderAssistant).to receive(:call).and_return(nil)
    allow(ClientAssistant).to receive(:call).and_return(nil)
    allow(ClientAssistant).to receive(:call_search_mode).and_return(nil)
    allow(OnboardingService).to receive(:call).and_return(nil)
  end

  describe ".call" do
    context "when phone matches a provider" do
      let(:provider) { build_stubbed(:provider) }

      before do
        # Stub the includes chain that ProviderConversationHandler uses
        provider_scope = instance_double(ActiveRecord::Relation)
        allow(Provider).to receive(:includes).and_return(provider_scope)
        allow(provider_scope).to receive(:find_by).with(phone: provider.phone).and_return(provider)
        allow(provider_scope).to receive(:find_by).with(short_uuid: anything).and_return(nil)
        allow(Provider).to receive(:find_by).with(short_uuid: anything).and_return(nil)
      end

      it "routes to ProviderAssistant" do
        ProviderConversationHandler.call(from: provider.phone, body: "Hola", media_url: nil)

        expect(ProviderAssistant).to have_received(:call).with(
          provider: provider, body: "Hola", media_url: nil
        )
      end

      it "routes to ProviderAssistant regardless of body content" do
        bodies = [ "Hola", "ok", "123", "", nil, SecureRandom.hex(4) ]

        bodies.each do |body|
          ProviderConversationHandler.call(from: provider.phone, body: body, media_url: nil)
        end

        expect(ProviderAssistant).to have_received(:call).at_least(bodies.length).times
      end

      it "does not route to ClientAssistant" do
        ProviderConversationHandler.call(from: provider.phone, body: "anything", media_url: nil)

        expect(ClientAssistant).not_to have_received(:call)
      end

      it "does not route to OnboardingService" do
        ProviderConversationHandler.call(from: provider.phone, body: "anything", media_url: nil)

        expect(OnboardingService).not_to have_received(:call)
      end
    end

    # Note: Client routing via short_uuid is now handled by ClientMessageJob → ClientAssistantOrchestrator
    # ProviderConversationHandler only handles provider number messages (providers and onboarding)

    context "when sender is unknown and body matches no provider" do
      let(:unknown_phone) { "5218888888888" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get).and_return(nil)
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "sends the welcome message" do
        ProviderConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: unknown_phone,
          message: I18n.t('elisa.provider.onboarding.welcome'),
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )
      end

      it "stores onboarding_welcome state in Redis" do
        ProviderConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{unknown_phone}",
          86_400,
          a_string_matching(/"stage":"onboarding_welcome"/)
        )
      end

      it "does not route to ProviderAssistant" do
        ProviderConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(ProviderAssistant).not_to have_received(:call)
      end

      it "does not route to ClientAssistant" do
        ProviderConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(ClientAssistant).not_to have_received(:call)
      end

      it "does not route to OnboardingService" do
        ProviderConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(OnboardingService).not_to have_received(:call)
      end
    end

    context "when sender already received welcome and responds with any message" do
      let(:phone) { "5217777777777" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return({ stage: "onboarding_welcome" }.to_json)
      end

      it "routes directly to OnboardingService" do
        ProviderConversationHandler.call(from: phone, body: "Hola", media_url: nil)

        expect(OnboardingService).to have_received(:call).with(from: phone, body: "Hola")
      end

      it "does not send welcome message again" do
        ProviderConversationHandler.call(from: phone, body: "Hola", media_url: nil)

        expect(WhatsAppService).not_to have_received(:send_message)
      end

      it "routes any response directly to OnboardingService without routing question" do
        responses = ["hola", "ok", "cualquier cosa", "sí", "listo"]

        responses.each do |response|
          ProviderConversationHandler.call(from: phone, body: response, media_url: nil)
        end

        expect(OnboardingService).to have_received(:call).exactly(responses.length).times
      end
    end

    context "when sender is in onboarding stage" do
      let(:phone) { "5214444444444" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return({ stage: "collecting_name" }.to_json)
      end

      it "routes to OnboardingService" do
        ProviderConversationHandler.call(from: phone, body: "Miguel", media_url: nil)

        expect(OnboardingService).to have_received(:call).with(from: phone, body: "Miguel")
      end
    end

    context "when body is blank or nil" do
      let(:unknown_phone) { "5213333333333" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get).and_return(nil)
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "treats blank body as unknown sender" do
        ProviderConversationHandler.call(from: unknown_phone, body: "", media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: unknown_phone,
          message: I18n.t('elisa.provider.onboarding.welcome'),
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )
      end

      it "treats nil body as unknown sender" do
        ProviderConversationHandler.call(from: unknown_phone, body: nil, media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: unknown_phone,
          message: I18n.t('elisa.provider.onboarding.welcome'),
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )
      end
    end

  end

  describe "constants" do
    it "defines ONBOARDING_TTL as 24 hours" do
      expect(ProviderConversationHandler::ONBOARDING_TTL).to eq(86_400)
    end
  end

  describe "i18n messages" do
    it "welcome message is available in YAML" do
      welcome_message = I18n.t('elisa.provider.onboarding.welcome', locale: :es)
      expect(welcome_message).to include("Soy Elisa de Trato")
      expect(welcome_message).to include("crear tu perfil de técnico")
    end
  end
end
