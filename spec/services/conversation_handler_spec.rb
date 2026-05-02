# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConversationHandler, type: :service do
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
        allow(Provider).to receive(:find_by).with(phone: provider.phone).and_return(provider)
        allow(Provider).to receive(:find_by).with(short_uuid: anything).and_return(nil)
      end

      it "routes to ProviderAssistant" do
        ConversationHandler.call(from: provider.phone, body: "Hola", media_url: nil)

        expect(ProviderAssistant).to have_received(:call).with(
          provider: provider, body: "Hola", media_url: nil
        )
      end

      it "routes to ProviderAssistant regardless of body content" do
        bodies = [ "Hola", "ok", "123", "", nil, SecureRandom.hex(4) ]

        bodies.each do |body|
          ConversationHandler.call(from: provider.phone, body: body, media_url: nil)
        end

        expect(ProviderAssistant).to have_received(:call).at_least(bodies.length).times
      end

      it "does not route to ClientAssistant" do
        ConversationHandler.call(from: provider.phone, body: "anything", media_url: nil)

        expect(ClientAssistant).not_to have_received(:call)
      end

      it "does not route to OnboardingService" do
        ConversationHandler.call(from: provider.phone, body: "anything", media_url: nil)

        expect(OnboardingService).not_to have_received(:call)
      end
    end

    context "when body matches a provider short_uuid from an unknown phone" do
      let(:provider) { build_stubbed(:provider) }
      let(:unknown_phone) { "5219999999999" }

      before do
        allow(Provider).to receive(:find_by).with(phone: unknown_phone).and_return(nil)
        allow(Provider).to receive(:find_by).with(short_uuid: provider.short_uuid).and_return(provider)
        allow(redis_mock).to receive(:get).and_return(nil)
      end

      it "routes to ClientAssistant" do
        ConversationHandler.call(from: unknown_phone, body: provider.short_uuid, media_url: nil)

        expect(ClientAssistant).to have_received(:call).with(
          provider: provider, from: unknown_phone, body: provider.short_uuid
        )
      end

      it "does not route to ProviderAssistant" do
        ConversationHandler.call(from: unknown_phone, body: provider.short_uuid, media_url: nil)

        expect(ProviderAssistant).not_to have_received(:call)
      end

      it "does not route to OnboardingService" do
        ConversationHandler.call(from: unknown_phone, body: provider.short_uuid, media_url: nil)

        expect(OnboardingService).not_to have_received(:call)
      end
    end

    context "when sender is unknown and body matches no provider" do
      let(:unknown_phone) { "5218888888888" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get).and_return(nil)
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "sends the welcome message" do
        ConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: unknown_phone,
          message: ConversationHandler::WELCOME_MESSAGE
        )
      end

      it "stores onboarding_welcome state in Redis" do
        ConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{unknown_phone}",
          86_400,
          a_string_matching(/"stage":"onboarding_welcome"/)
        )
      end

      it "does not route to ProviderAssistant" do
        ConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(ProviderAssistant).not_to have_received(:call)
      end

      it "does not route to ClientAssistant" do
        ConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(ClientAssistant).not_to have_received(:call)
      end

      it "does not route to OnboardingService" do
        ConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

        expect(OnboardingService).not_to have_received(:call)
      end
    end

    context "when sender already received welcome and responds with '2'" do
      let(:phone) { "5217777777777" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return({ stage: "onboarding_welcome" }.to_json)
      end

      it "routes to OnboardingService" do
        ConversationHandler.call(from: phone, body: "2", media_url: nil)

        expect(OnboardingService).to have_received(:call).with(from: phone, body: "2")
      end

      it "does not send welcome message again" do
        ConversationHandler.call(from: phone, body: "2", media_url: nil)

        expect(WhatsAppService).not_to have_received(:send_message)
      end
    end

    context "when sender already received welcome and responds with '1'" do
      let(:phone) { "5216666666666" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return({ stage: "onboarding_welcome" }.to_json)
      end

      it "routes to ClientAssistant in search mode" do
        ConversationHandler.call(from: phone, body: "1", media_url: nil)

        expect(ClientAssistant).to have_received(:call_search_mode).with(from: phone, body: "1")
      end

      it "does not send welcome message" do
        ConversationHandler.call(from: phone, body: "1", media_url: nil)

        expect(WhatsAppService).not_to have_received(:send_message)
      end
    end

    context "when sender already received welcome and responds with something else" do
      let(:phone) { "5215555555555" }

      before do
        allow(Provider).to receive(:find_by).and_return(nil)
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return({ stage: "onboarding_welcome" }.to_json)
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "repeats the welcome message" do
        ConversationHandler.call(from: phone, body: "hola", media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: ConversationHandler::WELCOME_MESSAGE
        )
      end

      it "does not route to any assistant" do
        ConversationHandler.call(from: phone, body: "hola", media_url: nil)

        expect(ProviderAssistant).not_to have_received(:call)
        expect(ClientAssistant).not_to have_received(:call)
        expect(OnboardingService).not_to have_received(:call)
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
        ConversationHandler.call(from: phone, body: "Miguel", media_url: nil)

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
        ConversationHandler.call(from: unknown_phone, body: "", media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: unknown_phone,
          message: ConversationHandler::WELCOME_MESSAGE
        )
      end

      it "treats nil body as unknown sender" do
        ConversationHandler.call(from: unknown_phone, body: nil, media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: unknown_phone,
          message: ConversationHandler::WELCOME_MESSAGE
        )
      end
    end

    context "when body has whitespace around short_uuid" do
      let(:provider) { build_stubbed(:provider) }
      let(:unknown_phone) { "5212222222222" }

      before do
        allow(Provider).to receive(:find_by).with(phone: unknown_phone).and_return(nil)
        allow(Provider).to receive(:find_by).with(short_uuid: provider.short_uuid).and_return(provider)
        allow(redis_mock).to receive(:get).and_return(nil)
      end

      it "strips whitespace and matches short_uuid" do
        ConversationHandler.call(from: unknown_phone, body: "  #{provider.short_uuid}  ", media_url: nil)

        expect(ClientAssistant).to have_received(:call).with(
          provider: provider, from: unknown_phone, body: "  #{provider.short_uuid}  "
        )
      end
    end
  end

  describe "constants" do
    it "defines WELCOME_MESSAGE" do
      expect(ConversationHandler::WELCOME_MESSAGE).to include("¿Estás buscando un técnico")
      expect(ConversationHandler::WELCOME_MESSAGE).to include("*1*")
      expect(ConversationHandler::WELCOME_MESSAGE).to include("*2*")
    end

    it "defines ONBOARDING_TTL as 24 hours" do
      expect(ConversationHandler::ONBOARDING_TTL).to eq(86_400)
    end
  end
end
