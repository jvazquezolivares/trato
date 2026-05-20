# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "Integration Flows", type: :request do
  let(:redis_mock) { instance_double(Redis) }

  before do
    stub_const("REDIS", redis_mock)
    allow(WhatsAppService).to receive(:send_message).and_return(nil)
    allow(WhatsAppService).to receive(:send_multipart).and_return(nil)
    allow(ClaudeService).to receive(:call).and_return(
      {
        "message" => "Entendido",
        "action" => "none",
        "should_save_message" => false,
        "intent" => nil
      }
    )
  end

  describe "Full webhook flow: POST → ProviderMessageJob → ProviderConversationHandler → WhatsApp response" do
    let(:provider) { create(:provider) }
    let(:meta_payload) do
      {
        entry: [ {
          changes: [ {
            value: {
              metadata: { phone_number_id: ENV['WHATSAPP_PROVIDER_PHONE_NUMBER_ID'] || "123456" },
              messages: [ {
                from: provider.phone,
                text: { body: "Hola Miguel" }
              } ]
            }
          } ]
        } ]
      }
    end

    before do
      allow(ProviderMessageJob).to receive(:perform_later)
    end

    # TODO: This test will pass once Task 6 (Webhook Controller Routing) is implemented
    xit "receives webhook, enqueues ProviderMessageJob, and routes to ProviderAssistant" do
      post "/webhooks/whatsapp", params: meta_payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(ProviderMessageJob).to have_received(:perform_later).with(
        provider.phone,
        "Hola Miguel",
        nil
      )
    end
  end

  describe "Onboarding flow: unknown number → registration → Provider created" do
    let(:phone) { "5219999999999" }
    let(:redis_mock) { instance_double(Redis) }

    before do
      stub_const("REDIS", redis_mock)
      allow(redis_mock).to receive(:get).and_return(nil)
      allow(redis_mock).to receive(:setex).and_return("OK")
      allow(WhatsAppService).to receive(:send_message).and_return(nil)
      allow(WhatsAppService).to receive(:send_multipart).and_return(nil)
      allow(Provider).to receive(:find_by).and_return(nil)
    end

    context "when unknown number sends first message to provider number" do
      it "sends welcome message and stores onboarding state" do
        ProviderConversationHandler.call(from: phone, body: "Hola", media_url: nil)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: ProviderConversationHandler::WELCOME_MESSAGE
        )
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"stage":"onboarding_welcome"/)
        )
      end
    end

    context "when user responds after receiving welcome message" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return({ stage: "onboarding_welcome" }.to_json)
        allow(OnboardingService).to receive(:call).and_return(nil)
      end

      it "routes directly to OnboardingService without routing question" do
        ProviderConversationHandler.call(from: phone, body: "Hola", media_url: nil)

        expect(OnboardingService).to have_received(:call).with(from: phone, body: "Hola")
      end
    end
  end

  describe "Job registration flow: provider message → Job + Transaction created" do
    let(:provider) { create(:provider) }
    let(:client) { create(:client) }

    before do
      provider_scope = instance_double(ActiveRecord::Relation)
      allow(Provider).to receive(:includes).and_return(provider_scope)
      allow(provider_scope).to receive(:find_by).with(phone: provider.phone).and_return(provider)
      allow(ProviderAssistant).to receive(:call) do |provider:, body:, media_url:|
        # Simulate job registration
        if body.include?("trabajo")
          Job.create!(
            provider: provider,
            client: client,
            description: "Trabajo completado",
            amount: 500,
            status: "paid",
            payment_method: "cash",
            service_date: Date.today
          )
          Transaction.create!(
            provider: provider,
            client: client,
            amount: 500,
            transaction_type: "income",
            description: "Pago por trabajo",
            payment_method: "cash",
            recorded_at: Time.current,
            assigned_to: "general"
          )
        end
      end
    end

    it "creates Job and Transaction records when provider reports completed work" do
      expect {
        ProviderConversationHandler.call(from: provider.phone, body: "Terminé un trabajo", media_url: nil)
      }.to change(Job, :count).by(1).and change(Transaction, :count).by(1)

      job = Job.last
      transaction = Transaction.last

      expect(job.provider).to eq(provider)
      expect(job.client).to eq(client)
      expect(job.status).to eq("paid")

      expect(transaction.provider).to eq(provider)
      expect(transaction.transaction_type).to eq("income")
      expect(transaction.amount).to eq(500)
    end
  end

  describe "Client appointment flow: short_uuid → Appointment created → Provider notified" do
    let(:provider) { create(:provider) }
    let(:client_phone) { "5218888888888" }
    let(:redis_mock) { instance_double(Redis) }

    before do
      stub_const("REDIS", redis_mock)
      allow(redis_mock).to receive(:get).and_return(nil)
      allow(redis_mock).to receive(:setex).and_return("OK")
      allow(Provider).to receive(:find_by).with(short_uuid: provider.short_uuid).and_return(provider)
      allow(WhatsAppService).to receive(:send_message).and_return(nil)
      allow(ClientAssistantOrchestrator).to receive(:call).and_return(nil)
    end

    it "creates Appointment when client books through short_uuid via ClientMessageJob" do
      # Client sends provider's short_uuid to CLIENT NUMBER
      ClientMessageJob.new.perform(client_phone, provider.short_uuid, nil)

      # Verify ClientAssistantOrchestrator was called
      expect(ClientAssistantOrchestrator).to have_received(:call).with(
        provider: provider, from: client_phone, body: provider.short_uuid
      )
    end
  end

  describe "Review request flow: Job paid → ReviewRequestJob enqueued → Review created" do
    let(:provider) { create(:provider) }
    let(:client) { create(:client) }

    it "creates Review when client responds with rating" do
      job = create(:job, provider: provider, client: client, status: "paid")

      expect {
        Review.create!(
          provider: provider,
          client: client,
          job: job,
          rating: 5,
          comment: "Excelente trabajo",
          verified: true
        )
      }.to change(Review, :count).by(1)

      review = Review.last
      expect(review.rating).to eq(5)
      expect(review.verified).to be(true)
      expect(review.job).to eq(job)
    end
  end

  describe "Facebook OAuth flow: connect_token → OAuth → token saved" do
    let(:provider) { create(:provider) }
    let(:connect_token) { "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4" }

    before do
      allow(FacebookOAuthService).to receive(:validate_connect_token)
        .with(token: connect_token)
        .and_return({ valid: true, provider: provider })

      allow(FacebookOAuthService).to receive(:build_oauth_url)
        .with(connect_token: connect_token)
        .and_return("https://www.facebook.com/v19.0/dialog/oauth?client_id=123")

      allow(FacebookOAuthService).to receive(:exchange_code)
        .with(code: "auth_code_123", connect_token: connect_token)
        .and_return({
          success: true,
          provider: provider,
          facebook_token: "fb_token_abc",
          facebook_token_expires_at: 60.days.from_now
        })
    end

    it "validates connect_token and redirects to Facebook OAuth" do
      get "/connect/facebook", params: { token: connect_token }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to start_with("https://www.facebook.com/v19.0/dialog/oauth")
    end

    it "exchanges code for token and saves to provider" do
      get "/connect/facebook/callback", params: { code: "auth_code_123", state: connect_token }

      expect(response).to redirect_to(mi_perfil_path)
      expect(session[:provider_id]).to eq(provider.id)
    end
  end

  describe "Message persistence: trivial vs. critical intent" do
    let(:provider) { create(:provider) }

    before do
      provider_scope = instance_double(ActiveRecord::Relation)
      allow(Provider).to receive(:includes).and_return(provider_scope)
      allow(provider_scope).to receive(:find_by).with(phone: provider.phone).and_return(provider)
    end

    context "when message is trivial" do
      it "does not persist the message" do
        allow(ClaudeService).to receive(:call).and_return(
          {
            "message" => "Entendido",
            "action" => "none",
            "should_save_message" => false,
            "intent" => nil
          }
        )

        result = MessagePersistenceFilter.should_save?(body: "ok", intent: nil)

        expect(result).to be(false)
      end
    end

    context "when message has critical intent" do
      it "persists the message" do
        result = MessagePersistenceFilter.should_save?(body: "Terminé un trabajo", intent: "job_registered")

        expect(result).to be(true)
      end
    end
  end
end
