# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProviderMessageJob, type: :job do
  describe "#perform" do
    let(:from) { "5212211234567" }
    let(:body) { "Hola, necesito ayuda" }
    let(:media_url) { "https://example.com/image.jpg" }

    before do
      allow(ProviderConversationHandler).to receive(:call)
    end

    context "when called with all parameters" do
      it "delegates to ProviderConversationHandler with from, body, and media_url" do
        described_class.new.perform(from, body, media_url)

        expect(ProviderConversationHandler).to have_received(:call).with(
          from: from,
          body: body,
          media_url: media_url
        )
      end
    end

    context "when called without media_url" do
      it "delegates to ProviderConversationHandler with from and body only" do
        described_class.new.perform(from, body)

        expect(ProviderConversationHandler).to have_received(:call).with(
          from: from,
          body: body,
          media_url: nil
        )
      end
    end

    context "when called with nil media_url explicitly" do
      it "delegates to ProviderConversationHandler with nil media_url" do
        described_class.new.perform(from, body, nil)

        expect(ProviderConversationHandler).to have_received(:call).with(
          from: from,
          body: body,
          media_url: nil
        )
      end
    end
  end
end
