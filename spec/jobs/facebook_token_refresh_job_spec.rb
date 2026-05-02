# frozen_string_literal: true

require "rails_helper"

RSpec.describe FacebookTokenRefreshJob, type: :job do
  describe "#perform" do
    it "delegates to FacebookOAuthService.refresh_expiring_tokens" do
      expect(FacebookOAuthService).to receive(:refresh_expiring_tokens)

      described_class.new.perform
    end

    context "when there are providers with expiring tokens" do
      let(:provider) do
        instance_double(
          Provider,
          id: 1,
          name: "Miguel García",
          phone: "5212211234567",
          facebook_token: "expiring_token",
          facebook_token_expires_at: 5.days.from_now
        )
      end

      it "calls refresh_expiring_tokens which processes each provider" do
        expect(FacebookOAuthService).to receive(:refresh_expiring_tokens).once

        described_class.new.perform
      end
    end

    context "when no providers have expiring tokens" do
      it "completes without errors" do
        allow(FacebookOAuthService).to receive(:refresh_expiring_tokens)

        expect { described_class.new.perform }.not_to raise_error
      end
    end
  end

  describe "job configuration" do
    it "uses the default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
