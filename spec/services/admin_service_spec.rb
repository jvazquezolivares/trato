# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminService do
  describe ".valid_credentials?" do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ADMIN_USERNAME", "").and_return("admin")
      allow(ENV).to receive(:fetch).with("ADMIN_PASSWORD", "").and_return("secret123")
    end

    context "when credentials match" do
      it "returns true" do
        result = described_class.valid_credentials?(username: "admin", password: "secret123")
        expect(result).to be true
      end
    end

    context "when username does not match" do
      it "returns false" do
        result = described_class.valid_credentials?(username: "wrong", password: "secret123")
        expect(result).to be false
      end
    end

    context "when password does not match" do
      it "returns false" do
        result = described_class.valid_credentials?(username: "admin", password: "wrong")
        expect(result).to be false
      end
    end

    context "when env vars are blank" do
      before do
        allow(ENV).to receive(:fetch).with("ADMIN_USERNAME", "").and_return("")
        allow(ENV).to receive(:fetch).with("ADMIN_PASSWORD", "").and_return("")
      end

      it "returns false" do
        result = described_class.valid_credentials?(username: "", password: "")
        expect(result).to be false
      end
    end
  end

  describe ".generate_confirmation_code" do
    let(:redis_mock) { instance_double(Redis) }

    before do
      stub_const("REDIS", redis_mock)
      allow(redis_mock).to receive(:setex)
      allow(redis_mock).to receive(:del)
      allow(WhatsAppService).to receive(:send_message)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ADMIN_EMAIL", "").and_return("admin@trato.mx")
    end

    it "generates a 6-digit code" do
      code = described_class.generate_confirmation_code
      expect(code).to match(/\A\d{6}\z/)
    end

    it "stores the code in Redis with TTL" do
      expect(redis_mock).to receive(:setex).with("admin_otp:code", 600, anything)
      described_class.generate_confirmation_code
    end

    it "sends the code via WhatsApp" do
      expect(WhatsAppService).to receive(:send_message).with(
        to: "admin@trato.mx",
        message: a_string_matching(/Código de acceso/)
      )
      described_class.generate_confirmation_code
    end
  end

  describe ".verify_confirmation_code" do
    let(:redis_mock) { instance_double(Redis) }

    before do
      stub_const("REDIS", redis_mock)
      allow(redis_mock).to receive(:get).with("admin_otp:attempts").and_return(nil)
    end

    context "when code is valid" do
      before do
        allow(redis_mock).to receive(:get).with("admin_otp:code").and_return("123456")
        allow(redis_mock).to receive(:del)
      end

      it "returns success" do
        result = described_class.verify_confirmation_code(code: "123456")
        expect(result[:success]).to be true
      end

      it "cleans up Redis keys" do
        expect(redis_mock).to receive(:del).with("admin_otp:code")
        expect(redis_mock).to receive(:del).with("admin_otp:attempts")
        described_class.verify_confirmation_code(code: "123456")
      end
    end

    context "when code is invalid" do
      before do
        allow(redis_mock).to receive(:get).with("admin_otp:code").and_return("123456")
        allow(redis_mock).to receive(:setex)
      end

      it "returns invalid error" do
        result = described_class.verify_confirmation_code(code: "000000")
        expect(result).to eq({ success: false, error: :invalid })
      end

      it "increments attempt counter" do
        expect(redis_mock).to receive(:setex).with("admin_otp:attempts", 600, "1")
        described_class.verify_confirmation_code(code: "000000")
      end
    end

    context "when code has expired" do
      before do
        allow(redis_mock).to receive(:get).with("admin_otp:code").and_return(nil)
      end

      it "returns expired error" do
        result = described_class.verify_confirmation_code(code: "123456")
        expect(result).to eq({ success: false, error: :expired })
      end
    end

    context "when max attempts reached" do
      before do
        allow(redis_mock).to receive(:get).with("admin_otp:attempts").and_return("5")
      end

      it "returns max_attempts error" do
        result = described_class.verify_confirmation_code(code: "123456")
        expect(result).to eq({ success: false, error: :max_attempts })
      end
    end
  end

  describe ".dashboard_stats" do
    it "returns a hash with all required metrics" do
      stats = described_class.dashboard_stats
      expect(stats).to include(
        :active_providers,
        :conversations_today,
        :jobs_this_month,
        :estimated_monthly_cost
      )
    end

    context "with data in the database" do
      let!(:active_provider) { create(:provider, active: true) }
      let!(:inactive_provider) { create(:provider, active: false) }

      it "counts active providers correctly" do
        stats = described_class.dashboard_stats
        expect(stats[:active_providers]).to eq(1)
      end
    end
  end

  describe ".recent_activity" do
    let!(:provider) { create(:provider) }
    let!(:client) { create(:client) }

    context "with recent jobs" do
      let!(:job) do
        create(:job, provider: provider, client: client,
               description: "Reparación de fuga", amount: 1500)
      end

      it "includes job activity" do
        activities = described_class.recent_activity(limit: 5)
        expect(activities).not_to be_empty
        expect(activities.first[:type]).to eq(:job)
      end
    end

    context "with no data" do
      it "returns an empty array" do
        activities = described_class.recent_activity(limit: 5)
        expect(activities).to be_empty
      end
    end
  end

  describe ".provider_status_breakdown" do
    let!(:active_provider) { create(:provider, active: true) }
    let!(:inactive_provider) { create(:provider, active: false) }

    it "returns correct breakdown" do
      breakdown = described_class.provider_status_breakdown
      expect(breakdown[:total]).to eq(2)
      expect(breakdown[:active]).to eq(1)
      expect(breakdown[:inactive]).to eq(1)
      expect(breakdown[:active_percentage]).to eq(50.0)
    end
  end

  describe ".providers_list" do
    let!(:active_provider) { create(:provider, active: true, city: "Veracruz", name: "Miguel") }
    let!(:inactive_provider) { create(:provider, active: false, city: "Puebla", name: "Carlos") }

    context "without filters" do
      it "returns all providers" do
        providers = described_class.providers_list
        expect(providers.count).to eq(2)
      end
    end

    context "with status filter" do
      it "filters active providers" do
        providers = described_class.providers_list(status: "active")
        expect(providers.count).to eq(1)
        expect(providers.first.name).to eq("Miguel")
      end

      it "filters inactive providers" do
        providers = described_class.providers_list(status: "inactive")
        expect(providers.count).to eq(1)
        expect(providers.first.name).to eq("Carlos")
      end
    end

    context "with city filter" do
      it "filters by city" do
        providers = described_class.providers_list(city: "Veracruz")
        expect(providers.count).to eq(1)
        expect(providers.first.city).to eq("Veracruz")
      end
    end

    context "with search filter" do
      it "searches by name" do
        providers = described_class.providers_list(search: "Miguel")
        expect(providers.count).to eq(1)
      end
    end
  end

  describe ".provider_detail" do
    let!(:provider) { create(:provider) }

    context "when provider exists" do
      it "returns provider detail hash" do
        detail = described_class.provider_detail(provider.id)
        expect(detail).to include(:provider, :financial_summary, :recent_conversations, :recent_jobs)
        expect(detail[:provider]).to eq(provider)
      end
    end

    context "when provider does not exist" do
      it "returns nil" do
        detail = described_class.provider_detail(-1)
        expect(detail).to be_nil
      end
    end
  end

  describe ".conversations_list" do
    let!(:provider) { create(:provider) }
    let!(:conversation) do
      create(:conversation, provider: provider, phone: "5212219876543",
             stage: "active", last_message_at: Time.current)
    end

    context "without filters" do
      it "returns all conversations" do
        conversations = described_class.conversations_list
        expect(conversations.count).to eq(1)
      end
    end

    context "with stage filter" do
      it "filters by stage" do
        conversations = described_class.conversations_list(stage: "active")
        expect(conversations.count).to eq(1)
      end

      it "returns empty for non-matching stage" do
        conversations = described_class.conversations_list(stage: "escalated")
        expect(conversations.count).to eq(0)
      end
    end
  end

  describe ".conversation_detail" do
    let!(:provider) { create(:provider) }
    let!(:conversation) { create(:conversation, provider: provider, phone: "5212219876543") }

    context "when conversation exists" do
      it "returns conversation detail hash" do
        detail = described_class.conversation_detail(conversation.id)
        expect(detail).to include(:conversation, :messages, :provider)
        expect(detail[:conversation]).to eq(conversation)
      end
    end

    context "when conversation does not exist" do
      it "returns nil" do
        detail = described_class.conversation_detail(-1)
        expect(detail).to be_nil
      end
    end
  end

  describe ".financial_summary" do
    it "returns a hash with all required financial metrics" do
      summary = described_class.financial_summary
      expect(summary).to include(
        :platform_income,
        :platform_expenses,
        :net_revenue,
        :total_providers,
        :active_providers,
        :estimated_infrastructure_cost
      )
    end
  end

  describe ".providers_financial_list" do
    let!(:provider) { create(:provider, active: true) }

    it "returns financial data per active provider" do
      list = described_class.providers_financial_list
      expect(list).not_to be_empty
      expect(list.first).to include(:provider, :income_this_month, :jobs_this_month)
    end
  end
end
