# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProviderPanelService do
  let(:provider) { create(:provider, name: "Miguel García", city: "Veracruz", short_uuid: "a3f8c2d1") }

  describe ".call" do
    subject(:panel) { described_class.call(provider) }

    it "returns a ProviderPanelService instance" do
      expect(panel).to be_a(ProviderPanelService)
    end

    it "loads the provider" do
      expect(panel.provider).to eq(provider)
    end
  end

  describe "#categories" do
    subject(:panel) { described_class.call(provider) }

    context "when provider has categories" do
      before do
        create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)
        create(:provider_category, provider: provider, name: "Albañil", slug: "albanil", primary: false)
      end

      it "loads categories ordered by primary first" do
        expect(panel.categories.first.name).to eq("Fontanero")
        expect(panel.categories.first.primary?).to be true
      end

      it "identifies the primary category" do
        expect(panel.primary_category.name).to eq("Fontanero")
      end
    end

    context "when provider has no categories" do
      it "returns empty collection" do
        expect(panel.categories).to be_empty
      end

      it "returns nil for primary category" do
        expect(panel.primary_category).to be_nil
      end
    end
  end

  describe "#metrics" do
    subject(:panel) { described_class.call(provider) }

    let(:client) { create(:client) }

    context "when provider has activity this month" do
      before do
        create(:job, provider: provider, client: client, service_date: Date.current, status: "paid")
        create(:job, provider: provider, client: client, service_date: Date.current, status: "partial")
        create(:transaction, provider: provider, transaction_type: "income", amount: 1500, recorded_at: Time.current)
        create(:transaction, provider: provider, transaction_type: "income", amount: 2000, recorded_at: Time.current)

        job = create(:job, provider: provider, client: client)
        create(:review, provider: provider, client: client, job: job, rating: 5, verified: true, created_at: Time.current)
      end

      it "counts jobs this month" do
        expect(panel.metrics[:jobs_this_month]).to eq(3)
      end

      it "sums income this month" do
        expect(panel.metrics[:income_this_month]).to eq(3500)
      end

      it "calculates average rating" do
        expect(panel.metrics[:average_rating]).to eq(5.0)
      end

      it "counts new reviews this month" do
        expect(panel.metrics[:new_reviews]).to eq(1)
      end
    end

    context "when provider has no activity" do
      it "returns zero for all metrics" do
        expect(panel.metrics[:jobs_this_month]).to eq(0)
        expect(panel.metrics[:income_this_month]).to eq(0)
        expect(panel.metrics[:average_rating]).to eq(0.0)
        expect(panel.metrics[:new_reviews]).to eq(0)
      end
    end
  end

  describe "#social_status" do
    subject(:panel) { described_class.call(provider) }

    context "when Facebook is connected" do
      before do
        provider.update!(facebook_token: "fb_token", facebook_page_url: "https://facebook.com/miguel")
      end

      it "reports Facebook as connected" do
        expect(panel.social_status[:facebook_connected]).to be true
        expect(panel.social_status[:facebook_page_url]).to eq("https://facebook.com/miguel")
      end
    end

    context "when Facebook is not connected" do
      it "reports Facebook as not connected" do
        expect(panel.social_status[:facebook_connected]).to be false
      end
    end

    context "when Instagram is linked" do
      before { provider.update!(instagram_token: "ig_token") }

      it "reports Instagram as linked" do
        expect(panel.social_status[:instagram_linked]).to be true
      end
    end

    context "when Instagram is not linked" do
      it "reports Instagram as not linked" do
        expect(panel.social_status[:instagram_linked]).to be false
      end
    end
  end

  describe "#assistant_config" do
    subject(:panel) { described_class.call(provider) }

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("TRATO_WHATSAPP_NUMBER", "").and_return("522221234567")
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TRATO_WHATSAPP_NUMBER").and_return("522221234567")
    end

    it "includes the WhatsApp number" do
      expect(panel.assistant_config[:whatsapp_number]).to eq("522221234567")
    end

    it "includes a formatted phone number" do
      expect(panel.assistant_config[:formatted_number]).to include("+52")
    end

    it "includes the assistant link" do
      expect(panel.assistant_config[:assistant_link]).to include("wa.me")
      expect(panel.assistant_config[:assistant_link]).to include("a3f8c2d1")
    end

    it "includes the short_uuid" do
      expect(panel.assistant_config[:short_uuid]).to eq("a3f8c2d1")
    end

    it "includes the auto-reply message with the assistant link" do
      expect(panel.assistant_config[:auto_reply_message]).to include("Ahorita estoy trabajando")
      expect(panel.assistant_config[:auto_reply_message]).to include(provider.assistant_whatsapp_link)
    end
  end

  describe "#photo_slots_remaining" do
    subject(:panel) { described_class.call(provider) }

    context "when provider has 4 work photos" do
      before { create_list(:photo, 4, :work, provider: provider) }

      it "returns 6 remaining slots" do
        expect(panel.photo_slots_remaining).to eq(6)
      end

      it "is not at the limit" do
        expect(panel.photo_limit_reached?).to be false
      end
    end

    context "when provider has 10 work photos" do
      before { create_list(:photo, 10, :work, provider: provider) }

      it "returns 0 remaining slots" do
        expect(panel.photo_slots_remaining).to eq(0)
      end

      it "is at the limit" do
        expect(panel.photo_limit_reached?).to be true
      end
    end
  end
end
