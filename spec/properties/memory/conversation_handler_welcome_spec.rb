# frozen_string_literal: true

# Feature: trato-mvp, Property 3: ConversationHandler sends welcome for unknown senders
# **Validates: Requirements 1.3**
#
# For any phone number not present in providers.phone and any message body not
# matching any providers.short_uuid, the system SHALL always send the welcome
# message and never route to ProviderAssistant or ClientAssistant.

require "rails_helper"

RSpec.describe ConversationHandler, "P3: welcome on unknown sender", type: :property do
  let(:redis_mock) { instance_double(Redis) }

  before do
    stub_const("REDIS", redis_mock)
    allow(redis_mock).to receive(:get).and_return(nil)
    allow(redis_mock).to receive(:setex).and_return("OK")
    allow(Provider).to receive(:find_by).and_return(nil)
    allow(WhatsAppService).to receive(:send_message).and_return(nil)
    allow(ProviderAssistant).to receive(:call).and_return(nil)
    allow(ClientAssistant).to receive(:call).and_return(nil)
  end

  context "when sender is unknown and body matches no provider" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "sends the welcome message (iteration #{iteration + 1})" do
        unknown_phone = "521#{rand(1_000_000_000..9_999_999_999)}"
        random_body = [Faker::Lorem.sentence, Faker::Name.name, rand(100..999).to_s, "", nil].sample

        ConversationHandler.call(from: unknown_phone, body: random_body, media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: unknown_phone,
          message: ConversationHandler::WELCOME_MESSAGE
        )
      end
    end

    it "never routes to ProviderAssistant" do
      ConversationHandler.call(from: "5210000000000", body: "hola", media_url: nil)

      expect(ProviderAssistant).not_to have_received(:call)
    end

    it "never routes to ClientAssistant" do
      ConversationHandler.call(from: "5210000000000", body: "hola", media_url: nil)

      expect(ClientAssistant).not_to have_received(:call)
    end
  end

  context "when sender already received welcome and responds with '2'" do
    let(:phone) { "5219999999999" }

    before do
      allow(redis_mock).to receive(:get)
        .with("onboarding_state:#{phone}")
        .and_return({ stage: "onboarding_welcome" }.to_json)
      allow(OnboardingService).to receive(:call).and_return(nil)
    end

    it "routes to OnboardingService" do
      ConversationHandler.call(from: phone, body: "2", media_url: nil)

      expect(OnboardingService).to have_received(:call).with(from: phone, body: "2")
    end
  end

  context "when sender already received welcome and responds with '1'" do
    let(:phone) { "5218888888888" }

    before do
      allow(redis_mock).to receive(:get)
        .with("onboarding_state:#{phone}")
        .and_return({ stage: "onboarding_welcome" }.to_json)
      allow(ClientAssistant).to receive(:call_search_mode).and_return(nil)
    end

    it "routes to ClientAssistant in search mode" do
      ConversationHandler.call(from: phone, body: "1", media_url: nil)

      expect(ClientAssistant).to have_received(:call_search_mode).with(from: phone, body: "1")
    end
  end

  context "when sender already received welcome and responds with something else" do
    let(:phone) { "5217777777777" }

    before do
      allow(redis_mock).to receive(:get)
        .with("onboarding_state:#{phone}")
        .and_return({ stage: "onboarding_welcome" }.to_json)
    end

    it "repeats the welcome message" do
      ConversationHandler.call(from: phone, body: "hola", media_url: nil)

      expect(WhatsAppService).to have_received(:send_message).with(
        to: phone,
        message: ConversationHandler::WELCOME_MESSAGE
      )
    end
  end
end
