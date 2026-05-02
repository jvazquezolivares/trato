# frozen_string_literal: true

# Feature: trato-mvp, Property 1: ConversationHandler routes by phone match
# **Validates: Requirements 1.1**
#
# For any Provider record with a given phone number, a message arriving from
# that phone number SHALL always be routed to ProviderAssistant for that
# Provider, regardless of the message body content.

require "rails_helper"

RSpec.describe ConversationHandler, "P1: routing by phone match", type: :property do
  let(:provider) { build_stubbed(:provider) }

  before do
    allow(ProviderAssistant).to receive(:call).and_return(nil)
    allow(ClientAssistant).to receive(:call).and_return(nil)
    allow(OnboardingService).to receive(:call).and_return(nil)
  end

  context "when phone matches a provider" do
    before do
      # Stub the includes chain that ConversationHandler uses
      provider_scope = instance_double(ActiveRecord::Relation)
      allow(Provider).to receive(:includes).and_return(provider_scope)
      allow(provider_scope).to receive(:find_by).with(phone: provider.phone).and_return(provider)
      allow(provider_scope).to receive(:find_by).with(short_uuid: anything).and_return(nil)
    end

    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "routes to ProviderAssistant regardless of body content (iteration #{iteration + 1})" do
        random_body = [ Faker::Lorem.sentence, SecureRandom.hex(4), nil, "", "1", "2" ].sample

        ConversationHandler.call(from: provider.phone, body: random_body, media_url: nil)

        expect(ProviderAssistant).to have_received(:call).with(
          provider: provider, body: random_body, media_url: nil
        )
      end
    end

    it "never routes to ClientAssistant" do
      ConversationHandler.call(from: provider.phone, body: "anything", media_url: nil)

      expect(ClientAssistant).not_to have_received(:call)
    end

    it "never routes to OnboardingService" do
      ConversationHandler.call(from: provider.phone, body: "anything", media_url: nil)

      expect(OnboardingService).not_to have_received(:call)
    end
  end

  context "when phone does not match any provider" do
    let(:redis_mock) { instance_double(Redis) }
    let(:unknown_phone) { "521#{rand(1_000_000_000..9_999_999_999)}" }

    before do
      stub_const("REDIS", redis_mock)
      allow(redis_mock).to receive(:get).and_return(nil)
      allow(redis_mock).to receive(:setex).and_return("OK")
      allow(Provider).to receive(:find_by).and_return(nil)
      allow(WhatsAppService).to receive(:send_message).and_return(nil)
    end

    it "does not route to ProviderAssistant" do
      ConversationHandler.call(from: unknown_phone, body: "hola", media_url: nil)

      expect(ProviderAssistant).not_to have_received(:call)
    end
  end
end
