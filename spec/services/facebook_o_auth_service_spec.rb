# frozen_string_literal: true

require "rails_helper"

RSpec.describe FacebookOAuthService do
  let(:provider) do
    instance_double(
      Provider,
      id: 42,
      name: "Miguel García",
      phone: "5212211234567",
      facebook_token: "old_token_abc",
      facebook_token_expires_at: 5.days.from_now
    )
  end

  let(:connect_token) { "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4" }

  before do
    stub_const("REDIS", instance_double(Redis))
  end

  describe ".validate_connect_token" do
    context "when the token exists in Redis and provider is found" do
      before do
        allow(REDIS).to receive(:get).with("facebook_connect:#{connect_token}").and_return("42")
        allow(Provider).to receive(:find_by).with(id: "42").and_return(provider)
      end

      it "returns valid with the provider" do
        result = described_class.validate_connect_token(token: connect_token)

        expect(result[:valid]).to be true
        expect(result[:provider]).to eq(provider)
      end
    end

    context "when the token does not exist in Redis (expired)" do
      before do
        allow(REDIS).to receive(:get).with("facebook_connect:#{connect_token}").and_return(nil)
      end

      it "returns invalid with expired error" do
        result = described_class.validate_connect_token(token: connect_token)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq(:expired)
      end
    end

    context "when the token exists but provider is not found" do
      before do
        allow(REDIS).to receive(:get).with("facebook_connect:#{connect_token}").and_return("999")
        allow(Provider).to receive(:find_by).with(id: "999").and_return(nil)
      end

      it "returns invalid with provider_not_found error" do
        result = described_class.validate_connect_token(token: connect_token)

        expect(result[:valid]).to be false
        expect(result[:error]).to eq(:provider_not_found)
      end
    end
  end

  describe ".build_oauth_url" do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("APP_URL", "https://trato.mx").and_return("https://trato.mx")
      allow(ENV).to receive(:fetch).with("FACEBOOK_APP_ID").and_return("123456789")
    end

    it "returns a Facebook OAuth URL with required parameters" do
      url = described_class.build_oauth_url(connect_token: connect_token)

      expect(url).to start_with("https://www.facebook.com/v19.0/dialog/oauth?")
      expect(url).to include("client_id=123456789")
      expect(url).to include("state=#{connect_token}")
      expect(url).to include("response_type=code")
    end

    it "includes the callback redirect_uri" do
      url = described_class.build_oauth_url(connect_token: connect_token)

      expect(url).to include("redirect_uri=")
      expect(url).to include("connect%2Ffacebook%2Fcallback")
    end

    it "requests the required Facebook permissions" do
      url = described_class.build_oauth_url(connect_token: connect_token)

      expect(url).to include("pages_manage_posts")
      expect(url).to include("pages_read_engagement")
      expect(url).to include("instagram_basic")
      expect(url).to include("instagram_content_publish")
    end
  end

  describe ".exchange_code" do
    let(:auth_code) { "auth_code_from_facebook" }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("APP_URL", "https://trato.mx").and_return("https://trato.mx")
      allow(ENV).to receive(:fetch).with("FACEBOOK_APP_ID").and_return("123456789")
      allow(ENV).to receive(:fetch).with("FACEBOOK_APP_SECRET").and_return("secret_abc")
    end

    context "when the connect_token is invalid" do
      before do
        allow(REDIS).to receive(:get).with("facebook_connect:#{connect_token}").and_return(nil)
      end

      it "returns failure with error message" do
        result = described_class.exchange_code(code: auth_code, connect_token: connect_token)

        expect(result[:success]).to be false
        expect(result[:error]).to include("inválido o expirado")
      end
    end

    context "when the token exchange succeeds" do
      let(:short_lived_response) do
        instance_double(HTTParty::Response,
          success?: true,
          parsed_response: { "access_token" => "short_lived_token" })
      end

      let(:long_lived_response) do
        instance_double(HTTParty::Response,
          success?: true,
          parsed_response: { "access_token" => "long_lived_token", "expires_in" => 5_184_000 })
      end

      let(:pages_response) do
        instance_double(HTTParty::Response,
          success?: true,
          parsed_response: { "data" => [ { "id" => "page_123", "access_token" => "page_token_abc" } ] })
      end

      let(:ig_response) do
        instance_double(HTTParty::Response,
          success?: true,
          parsed_response: { "instagram_business_account" => { "id" => "ig_456" } })
      end

      before do
        allow(REDIS).to receive(:get).with("facebook_connect:#{connect_token}").and_return("42")
        allow(REDIS).to receive(:del).with("facebook_connect:#{connect_token}")
        allow(Provider).to receive(:find_by).with(id: "42").and_return(provider)
        allow(provider).to receive(:update!)

        # Stub the HTTP calls in order
        allow(HTTParty).to receive(:get).and_return(short_lived_response)

        # Short-lived token exchange
        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/oauth/access_token",
                query: hash_including(code: auth_code))
          .and_return(short_lived_response)

        # Long-lived token exchange
        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/oauth/access_token",
                query: hash_including(grant_type: "fb_exchange_token"))
          .and_return(long_lived_response)

        # Page token fetch
        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/me/accounts",
                query: hash_including(access_token: "long_lived_token"))
          .and_return(pages_response)

        # Instagram auto-link: page accounts + IG business account
        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/me/accounts",
                query: hash_including(access_token: "page_token_abc"))
          .and_return(pages_response)

        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/page_123",
                query: hash_including(fields: "instagram_business_account"))
          .and_return(ig_response)
      end

      it "returns success with the provider" do
        result = described_class.exchange_code(code: auth_code, connect_token: connect_token)

        expect(result[:success]).to be true
        expect(result[:provider]).to eq(provider)
      end

      it "saves the page token on the provider" do
        expect(provider).to receive(:update!).with(
          hash_including(facebook_token: "page_token_abc")
        )

        described_class.exchange_code(code: auth_code, connect_token: connect_token)
      end

      it "auto-links the Instagram token" do
        expect(provider).to receive(:update!).with(
          hash_including(instagram_token: "page_token_abc")
        )

        described_class.exchange_code(code: auth_code, connect_token: connect_token)
      end

      it "cleans up the connect_token from Redis" do
        expect(REDIS).to receive(:del).with("facebook_connect:#{connect_token}")

        described_class.exchange_code(code: auth_code, connect_token: connect_token)
      end
    end

    context "when the short-lived token exchange fails" do
      let(:failed_response) do
        instance_double(HTTParty::Response, success?: false, code: 400)
      end

      before do
        allow(REDIS).to receive(:get).with("facebook_connect:#{connect_token}").and_return("42")
        allow(Provider).to receive(:find_by).with(id: "42").and_return(provider)

        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/oauth/access_token",
                query: hash_including(code: auth_code))
          .and_return(failed_response)
      end

      it "returns failure" do
        result = described_class.exchange_code(code: auth_code, connect_token: connect_token)

        expect(result[:success]).to be false
        expect(result[:error]).to include("token de Facebook")
      end
    end
  end

  describe ".refresh_expiring_tokens" do
    let(:expiring_provider) do
      instance_double(
        Provider,
        id: 1,
        name: "Miguel García",
        phone: "5212211234567",
        facebook_token: "expiring_token",
        facebook_token_expires_at: 5.days.from_now
      )
    end

    let(:providers_scope) { double("providers_scope") }

    before do
      allow(Provider).to receive(:where).with(active: true).and_return(providers_scope)
      allow(providers_scope).to receive(:where).and_return(providers_scope)
      allow(providers_scope).to receive_message_chain(:where, :not).and_return(providers_scope)
    end

    context "when a provider's token is refreshed successfully" do
      let(:long_lived_response) do
        instance_double(HTTParty::Response,
          success?: true,
          parsed_response: { "access_token" => "refreshed_token", "expires_in" => 5_184_000 })
      end

      let(:pages_response) do
        instance_double(HTTParty::Response,
          success?: true,
          parsed_response: { "data" => [ { "id" => "page_123", "access_token" => "page_token" } ] })
      end

      let(:ig_response) do
        instance_double(HTTParty::Response,
          success?: true,
          parsed_response: { "instagram_business_account" => { "id" => "ig_456" } })
      end

      before do
        allow(expiring_provider).to receive(:update!)

        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/oauth/access_token",
                query: hash_including(grant_type: "fb_exchange_token"))
          .and_return(long_lived_response)

        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/me/accounts",
                query: hash_including(access_token: "refreshed_token"))
          .and_return(pages_response)

        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/page_123",
                query: hash_including(fields: "instagram_business_account"))
          .and_return(ig_response)
      end

      it "updates the provider's token and expiry" do
        expect(expiring_provider).to receive(:update!).with(
          hash_including(facebook_token: "refreshed_token")
        )

        described_class.refresh_token_for(expiring_provider)
      end

      it "returns true" do
        result = described_class.refresh_token_for(expiring_provider)

        expect(result).to be true
      end
    end

    context "when token refresh fails" do
      let(:failed_response) do
        instance_double(HTTParty::Response, success?: false, code: 400)
      end

      before do
        allow(HTTParty).to receive(:get)
          .with("https://graph.facebook.com/v19.0/oauth/access_token",
                query: hash_including(grant_type: "fb_exchange_token"))
          .and_return(failed_response)

        allow(REDIS).to receive(:setex)
        allow(WhatsAppService).to receive(:send_message)
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("APP_URL", "https://trato.mx").and_return("https://trato.mx")
      end

      it "notifies the provider via WhatsApp with a reconnect link" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212211234567",
          message: a_string_including("reconecta tu cuenta")
        )

        described_class.refresh_token_for(expiring_provider)
      end

      it "stores a new connect_token in Redis" do
        expect(REDIS).to receive(:setex).with(
          a_string_matching(/^facebook_connect:/),
          600,
          "1"
        )

        described_class.refresh_token_for(expiring_provider)
      end

      it "returns false" do
        result = described_class.refresh_token_for(expiring_provider)

        expect(result).to be false
      end
    end
  end

  describe ".notify_provider_reconnect" do
    before do
      allow(REDIS).to receive(:setex)
      allow(WhatsAppService).to receive(:send_message)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("APP_URL", "https://trato.mx").and_return("https://trato.mx")
    end

    it "generates a connect_token and stores it in Redis with 10-minute TTL" do
      expect(REDIS).to receive(:setex).with(
        a_string_matching(/^facebook_connect:[a-f0-9]{32}$/),
        600,
        "42"
      )

      described_class.notify_provider_reconnect(provider)
    end

    it "sends a WhatsApp message with the reconnect URL" do
      expect(WhatsAppService).to receive(:send_message).with(
        to: "5212211234567",
        message: a_string_including("trato.mx/connect/facebook?token=")
      )

      described_class.notify_provider_reconnect(provider)
    end

    it "includes the provider's name in the message" do
      expect(WhatsAppService).to receive(:send_message).with(
        to: "5212211234567",
        message: a_string_including("Miguel García")
      )

      described_class.notify_provider_reconnect(provider)
    end
  end
end
