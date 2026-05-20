# frozen_string_literal: true

# Feature: trato-mvp, Property 2: ProviderConversationHandler routes by short_uuid match
# **Validates: Requirements 1.2**
#
# For any Provider record with a given short_uuid, a message arriving from an
# unknown phone with a body equal to that short_uuid SHALL always be routed
# to ClientAssistant for that Provider.

require "rails_helper"

RSpec.describe ProviderConversationHandler, "P2: routing by short_uuid match", type: :property do
  let(:provider) { build_stubbed(:provider) }

  before do
    allow(ProviderAssistant).to receive(:call).and_return(nil)
    allow(ClientAssistant).to receive(:call).and_return(nil)
    allow(OnboardingService).to receive(:call).and_return(nil)
  end

  context "when body matches a provider short_uuid from an unknown phone" do
    before do
      allow(Provider).to receive(:find_by).and_return(nil)
      allow(Provider).to receive(:find_by).with(short_uuid: provider.short_uuid).and_return(provider)
    end

    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "routes to ClientAssistant for that provider (iteration #{iteration + 1})" do
        unknown_phone = "521#{rand(1_000_000_000..9_999_999_999)}"

        ProviderConversationHandler.call(from: unknown_phone, body: provider.short_uuid, media_url: nil)

        expect(ClientAssistant).to have_received(:call).with(
          provider: provider, from: unknown_phone, body: provider.short_uuid
        )
      end
    end

    it "never routes to ProviderAssistant" do
      ProviderConversationHandler.call(from: "521#{rand(1_000_000_000..9_999_999_999)}", body: provider.short_uuid)

      expect(ProviderAssistant).not_to have_received(:call)
    end

    it "never routes to OnboardingService" do
      ProviderConversationHandler.call(from: "521#{rand(1_000_000_000..9_999_999_999)}", body: provider.short_uuid)

      expect(OnboardingService).not_to have_received(:call)
    end
  end

  context "when body does not match any provider short_uuid" do
    let(:redis_mock) { instance_double(Redis) }
    let(:unknown_phone) { "521#{rand(1_000_000_000..9_999_999_999)}" }

    before do
      stub_const("REDIS", redis_mock)
      allow(redis_mock).to receive(:get).and_return(nil)
      allow(redis_mock).to receive(:setex).and_return("OK")
      allow(Provider).to receive(:find_by).and_return(nil)
      allow(WhatsAppService).to receive(:send_message).and_return(nil)
    end

    it "does not route to ClientAssistant" do
      ProviderConversationHandler.call(from: unknown_phone, body: "not_a_uuid", media_url: nil)

      expect(ClientAssistant).not_to have_received(:call)
    end
  end
end
