# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomepageService do
  describe ".call" do
    context "when loading featured providers" do
      it "returns active providers that have work photos" do
        provider = create(:provider, active: true)
        create(:photo, :work, provider: provider)

        result = described_class.call

        expect(result.featured_providers).to include(provider)
      end

      it "excludes providers without work photos" do
        create(:provider, active: true)

        result = described_class.call

        expect(result.featured_providers).to be_empty
      end

      it "excludes providers that only have a profile photo" do
        provider = create(:provider, active: true)
        create(:photo, :profile, provider: provider)

        result = described_class.call

        expect(result.featured_providers).to be_empty
      end

      it "excludes inactive providers" do
        provider = create(:provider, active: false)
        create(:photo, :work, provider: provider)

        result = described_class.call

        expect(result.featured_providers).to be_empty
      end

      it "limits results to 6 providers" do
        8.times do
          provider = create(:provider, active: true)
          create(:photo, :work, provider: provider)
        end

        result = described_class.call

        expect(result.featured_providers.size).to eq(6)
      end

      it "orders by most recently created first" do
        old_provider = create(:provider, active: true, created_at: 10.days.ago)
        create(:photo, :work, provider: old_provider)

        new_provider = create(:provider, active: true, created_at: 1.day.ago)
        create(:photo, :work, provider: new_provider)

        result = described_class.call
        providers = result.featured_providers.to_a

        expect(providers.first).to eq(new_provider)
        expect(providers.last).to eq(old_provider)
      end

      it "does not raise PG error when provider has multiple work photos" do
        provider = create(:provider, active: true)
        create_list(:photo, 3, :work, provider: provider)

        expect { described_class.call }.not_to raise_error
      end

      it "eager-loads associations to avoid N+1 queries" do
        3.times do
          provider = create(:provider, active: true)
          create(:photo, :work, provider: provider)
          create(:provider_category, provider: provider, primary: true)
        end

        result = described_class.call
        providers = result.featured_providers.to_a

        # Accessing eager-loaded associations should not trigger additional queries
        query_count = 0
        counter = lambda { |_name, _start, _finish, _id, payload|
          query_count += 1 unless payload[:name] == "SCHEMA" || payload[:cached]
        }

        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          providers.each do |provider|
            provider.provider_categories.to_a
            provider.photos.to_a
            provider.reviews.to_a
          end
        end

        expect(query_count).to eq(0)
      end
    end

    context "when loading trust metrics" do
      it "counts only active providers" do
        create(:provider, active: true)
        create(:provider, active: false)

        result = described_class.call

        expect(result.total_providers).to eq(1)
      end

      it "counts all jobs" do
        provider = create(:provider)
        client = create(:client)
        create_list(:job, 3, provider: provider, client: client)

        result = described_class.call

        expect(result.total_jobs).to eq(3)
      end

      it "counts only verified reviews" do
        provider = create(:provider)
        client = create(:client)
        job_verified = create(:job, provider: provider, client: client)
        job_unverified = create(:job, provider: provider, client: client)
        create(:review, provider: provider, client: client, job: job_verified, verified: true)
        create(:review, provider: provider, client: client, job: job_unverified, verified: false)

        result = described_class.call

        expect(result.total_reviews).to eq(1)
      end
    end

    context "when loading categories" do
      it "returns primary categories from active providers" do
        provider = create(:provider, active: true)
        create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)

        result = described_class.call

        expect(result.categories.map(&:name)).to include("Fontanero")
      end

      it "excludes secondary categories" do
        provider = create(:provider, active: true)
        create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)
        create(:provider_category, provider: provider, name: "Albañil", slug: "albanil", primary: false)

        result = described_class.call

        category_names = result.categories.map(&:name)
        expect(category_names).to include("Fontanero")
        expect(category_names).not_to include("Albañil")
      end

      it "excludes categories from inactive providers" do
        provider = create(:provider, active: false)
        create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)

        result = described_class.call

        expect(result.categories).to be_empty
      end

      it "returns distinct categories when multiple providers share the same one" do
        2.times do
          provider = create(:provider, active: true)
          create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)
        end

        result = described_class.call

        fontanero_count = result.categories.count { |c| c.name == "Fontanero" }
        expect(fontanero_count).to eq(1)
      end
    end

    context "when database is empty" do
      it "returns empty results without errors" do
        result = described_class.call

        expect(result.featured_providers).to be_empty
        expect(result.total_providers).to eq(0)
        expect(result.total_jobs).to eq(0)
        expect(result.total_reviews).to eq(0)
        expect(result.categories).to be_empty
      end
    end
  end
end
