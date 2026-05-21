# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::ProviderSearchService do
  let(:client_phone) { "5212219876543" }

  let(:search_response) do
    {
      "message" => "¿Qué tipo de servicio necesitas?",
      "action" => "none",
      "action_data" => {},
      "new_stage" => "searching",
      "updated_context" => {},
      "should_save_message" => false,
      "intent" => nil
    }
  end

  before do
    allow(ClaudeService).to receive(:call).and_return(search_response)
    allow(WhatsAppService).to receive(:send_message).and_return(true)
    allow(REDIS).to receive(:get).with("search_state:#{client_phone}").and_return(nil)
    allow(REDIS).to receive(:setex).and_return("OK")
  end

  describe ".call" do
    it "calls ClaudeService with search mode prompt" do
      described_class.call(from: client_phone, body: "Busco fontanero")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(
          model: :haiku,
          system_prompt: a_string_matching(/plataforma que conecta clientes/),
          user_message: "Busco fontanero"
        )
      )
    end

    it "sends reply to client" do
      described_class.call(from: client_phone, body: "Busco fontanero")

      expect(WhatsAppService).to have_received(:send_message).with(
        to: client_phone,
        message: search_response["message"]
      )
    end

    it "saves search context in Redis" do
      described_class.call(from: client_phone, body: "Busco fontanero")

      expect(REDIS).to have_received(:setex).with(
        "search_state:#{client_phone}",
        86_400,
        anything
      )
    end

    context "when search finds a single provider" do
      let(:found_provider) do
        instance_double(Provider, id: 2, name: "Carlos Ruiz", city: "Veracruz")
      end

      let(:found_categories) { double("categories") }
      let(:search_scope) { double("search_scope") }

      let(:search_response) do
        {
          "message" => "Encontré uno.",
          "action" => "search_provider",
          "action_data" => { "category" => "fontanero", "city" => "veracruz" },
          "new_stage" => "searching",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      before do
        allow(Provider).to receive(:where).with(active: true).and_return(search_scope)
        allow(search_scope).to receive(:where).and_return(search_scope)
        allow(search_scope).to receive(:joins).and_return(search_scope)
        allow(search_scope).to receive(:distinct).and_return(search_scope)
        allow(search_scope).to receive(:limit).with(5).and_return([ found_provider ])
        allow(search_scope).to receive(:one?).and_return(true)
        allow(search_scope).to receive(:first).and_return(found_provider)
        allow(found_provider).to receive(:provider_categories).and_return(found_categories)
        allow(found_categories).to receive(:pluck).with(:name).and_return([ "Fontanero" ])
        allow(REDIS).to receive(:del).and_return(1)
      end

      it "transitions to provider conversation" do
        described_class.call(from: client_phone, body: "Fontanero en Veracruz")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/Elisa.*asistente de Carlos Ruiz/)
        )
      end

      it "cleans up Redis search state" do
        described_class.call(from: client_phone, body: "Fontanero en Veracruz")

        expect(REDIS).to have_received(:del).with("search_state:#{client_phone}")
      end
    end
  end

  describe "#search_providers_by_zone_and_category" do
    let(:service) { described_class.new(from: client_phone, body: "test") }

    let!(:provider_in_zone) do
      Provider.create!(
        name: "Miguel García",
        phone: "5212291234567",
        city: "Veracruz",
        service_area: "Boca del Río, Centro, Mocambo",
        active: true,
        short_uuid: SecureRandom.hex(4)
      )
    end

    let!(:provider_different_zone) do
      Provider.create!(
        name: "Carlos López",
        phone: "5212291234568",
        city: "Veracruz",
        service_area: "Costa Verde, Infonavit Buenavista",
        active: true,
        short_uuid: SecureRandom.hex(4)
      )
    end

    let!(:provider_different_category) do
      Provider.create!(
        name: "Juan Pérez",
        phone: "5212291234569",
        city: "Veracruz",
        service_area: "Boca del Río, Centro",
        active: true,
        short_uuid: SecureRandom.hex(4)
      )
    end

    let!(:inactive_provider) do
      Provider.create!(
        name: "Pedro Inactive",
        phone: "5212291234570",
        city: "Veracruz",
        service_area: "Boca del Río",
        active: false,
        short_uuid: SecureRandom.hex(4)
      )
    end

    let!(:plomeria_category) do
      ProviderCategory.create!(
        name: "Plomería",
        slug: "plomeria",
        primary: true,
        provider: provider_in_zone
      )
    end

    let!(:electricidad_category) do
      ProviderCategory.create!(
        name: "Electricidad",
        slug: "electricidad",
        primary: true,
        provider: provider_different_category
      )
    end

    before do
      # Add plomeria category to provider_different_zone
      ProviderCategory.create!(
        name: "Plomería",
        slug: "plomeria",
        primary: false,
        provider: provider_different_zone
      )

      # Add plomeria category to inactive_provider
      ProviderCategory.create!(
        name: "Plomería",
        slug: "plomeria",
        primary: true,
        provider: inactive_provider
      )
    end

    context "when searching by zone and category" do
      it "returns active providers matching zone and category" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        expect(results).to include(provider_in_zone)
        expect(results).not_to include(provider_different_category)
        expect(results).not_to include(inactive_provider)
      end

      it "is case-insensitive for zone matching" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "BOCA DEL RÍO",
                               category_slug: "plomeria")

        expect(results).to include(provider_in_zone)
      end

      it "is case-insensitive for category slug matching" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "PLOMERIA")

        expect(results).to include(provider_in_zone)
      end

      it "returns empty when no providers match zone" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Nonexistent Zone",
                               category_slug: "plomeria")

        expect(results).to be_empty
      end

      it "returns empty when no providers match category" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "nonexistent-category")

        expect(results).to be_empty
      end

      it "eager loads reviews association" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        # Verify that reviews are eager loaded by checking association is loaded
        expect(results.first.association(:reviews).loaded?).to be true
      end

      it "eager loads provider_categories association" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        # Verify that provider_categories are eager loaded
        expect(results.first.association(:provider_categories).loaded?).to be true
      end
    end

    context "when there are 10 or fewer results" do
      before do
        # Create exactly 9 more providers (total 10 with provider_in_zone)
        9.times do |i|
          provider = Provider.create!(
            name: "Provider #{i}",
            phone: "52122912#{1000 + i}",
            city: "Veracruz",
            service_area: "Boca del Río",
            active: true,
            short_uuid: SecureRandom.hex(4)
          )

          ProviderCategory.create!(
            name: "Plomería",
            slug: "plomeria",
            primary: true,
            provider: provider
          )
        end
      end

      it "orders results randomly" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        expect(results.to_a.size).to eq(10)
        # Verify random ordering is applied (check SQL includes RANDOM())
        expect(results.to_sql).to include("RANDOM()")
        expect(results.to_sql).not_to include("AVG(reviews.rating)")
      end
    end

    context "when there are more than 10 results" do
      before do
        # Create 10 more providers (total 12 with existing ones)
        10.times do |i|
          provider = Provider.create!(
            name: "Provider #{i}",
            phone: "52122913#{1000 + i}",
            city: "Veracruz",
            service_area: "Boca del Río",
            active: true,
            short_uuid: SecureRandom.hex(4)
          )

          ProviderCategory.create!(
            name: "Plomería",
            slug: "plomeria",
            primary: true,
            provider: provider
          )

          # Add reviews to some providers to test rating ordering
          if i < 3
            client = Client.create!(
              name: "Client #{i}",
              phone: "52122999#{1000 + i}"
            )

            job = Job.create!(
              provider: provider,
              client: client,
              status: :completed,
              description: "Test job"
            )

            Review.create!(
              provider: provider,
              client: client,
              job: job,
              rating: 5,
              comment: "Excellent"
            )
          end
        end
      end

      it "orders by average rating DESC, then random" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        expect(results.to_a.size).to be > 10
        # Verify ordering includes both rating and random
        expect(results.to_sql).to include("AVG(reviews.rating)")
        expect(results.to_sql).to include("RANDOM()")
      end

      it "places top-rated providers first" do
        # Create a highly-rated provider
        top_provider = Provider.create!(
          name: "Top Rated Provider",
          phone: "5212291111111",
          city: "Veracruz",
          service_area: "Boca del Río",
          active: true,
          short_uuid: SecureRandom.hex(4)
        )

        ProviderCategory.create!(
          name: "Plomería",
          slug: "plomeria",
          primary: true,
          provider: top_provider
        )

        # Add multiple 5-star reviews
        3.times do |i|
          client = Client.create!(
            name: "Happy Client #{i}",
            phone: "52122988#{1000 + i}"
          )

          job = Job.create!(
            provider: top_provider,
            client: client,
            status: :completed,
            description: "Test job #{i}"
          )

          Review.create!(
            provider: top_provider,
            client: client,
            job: job,
            rating: 5,
            comment: "Amazing work!"
          )
        end

        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        # Top-rated provider should be in the first few results
        # (exact position may vary due to RANDOM() for ties)
        top_5_results = results.limit(5).to_a
        expect(top_5_results).to include(top_provider)
      end
    end

    context "when pagination is needed for > 10 results" do
      before do
        # Create 15 providers to test pagination
        15.times do |i|
          provider = Provider.create!(
            name: "Provider Page #{i + 1}",
            phone: "52122914#{1000 + i}",
            city: "Veracruz",
            service_area: "Boca del Río",
            active: true,
            short_uuid: SecureRandom.hex(4)
          )

          ProviderCategory.create!(
            name: "Plomería",
            slug: "plomeria",
            primary: true,
            provider: provider
          )

          # Add varying ratings to test ordering
          if i < 5
            # Top 5 providers get 5-star reviews
            client = Client.create!(
              name: "Client for Provider #{i}",
              phone: "52122977#{1000 + i}"
            )

            job = Job.create!(
              provider: provider,
              client: client,
              status: :completed,
              description: "Test job"
            )

            Review.create!(
              provider: provider,
              client: client,
              job: job,
              rating: 5,
              comment: "Excellent service"
            )
          elsif i < 10
            # Next 5 providers get 4-star reviews
            client = Client.create!(
              name: "Client for Provider #{i}",
              phone: "52122977#{1000 + i}"
            )

            job = Job.create!(
              provider: provider,
              client: client,
              status: :completed,
              description: "Test job"
            )

            Review.create!(
              provider: provider,
              client: client,
              job: job,
              rating: 4,
              comment: "Good service"
            )
          end
          # Last 5 providers have no reviews
        end
      end

      it "returns all matching providers without automatic limit" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        # Should return all 17 providers (15 new + 2 existing from before)
        expect(results.to_a.size).to be >= 15
      end

      it "can be paginated using limit and offset" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        # First page: 10 results
        page_1 = results.limit(10).to_a
        expect(page_1.size).to eq(10)

        # Second page: remaining results
        page_2 = results.offset(10).limit(10).to_a
        expect(page_2.size).to be > 0

        # Verify no overlap between pages
        page_1_ids = page_1.map(&:id)
        page_2_ids = page_2.map(&:id)
        expect(page_1_ids & page_2_ids).to be_empty
      end

      it "orders top-rated providers in first page" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        first_page = results.limit(10).to_a

        # Calculate average ratings for first page providers
        first_page_ratings = first_page.map do |provider|
          reviews = provider.reviews.to_a
          reviews.empty? ? 0 : reviews.sum(&:rating).to_f / reviews.size
        end

        # First page should have higher average ratings overall
        # At least half should have ratings >= 4
        high_rated_count = first_page_ratings.count { |rating| rating >= 4.0 }
        expect(high_rated_count).to be >= 5
      end

      it "maintains consistent ordering for rated providers" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        first_page = results.limit(10).to_a

        # Verify that providers with reviews appear before those without
        providers_with_reviews = first_page.select { |p| p.reviews.any? }
        providers_without_reviews = first_page.select { |p| p.reviews.empty? }

        # Most providers in first page should have reviews (due to rating ordering)
        expect(providers_with_reviews.size).to be >= providers_without_reviews.size
      end

      it "includes provider basic info for list display" do
        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        first_provider = results.first

        # Verify provider has necessary attributes for display
        expect(first_provider.name).to be_present
        expect(first_provider.city).to be_present
        expect(first_provider.service_area).to be_present
        expect(first_provider.short_uuid).to be_present

        # Verify associations are loaded
        expect(first_provider.association(:reviews).loaded?).to be true
        expect(first_provider.association(:provider_categories).loaded?).to be true
      end

      it "handles pagination with exactly 10 results boundary" do
        # Count current providers
        current_count = service.send(:search_providers_by_zone_and_category,
                                      zone: "Boca del Río",
                                      category_slug: "plomeria").to_a.size

        # Remove providers to get exactly 10
        providers_to_remove = current_count - 10
        if providers_to_remove > 0
          Provider.where("name LIKE ?", "Provider Page%").limit(providers_to_remove).destroy_all
        end

        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        # Should have exactly 10 providers now
        expect(results.to_a.size).to eq(10)

        # Should use random ordering (not rating-based) for exactly 10
        expect(results.to_sql).to include("RANDOM()")
      end

      it "handles pagination with 11 results (just over boundary)" do
        # Count current providers
        current_count = service.send(:search_providers_by_zone_and_category,
                                      zone: "Boca del Río",
                                      category_slug: "plomeria").to_a.size

        # Remove providers to get exactly 11
        providers_to_remove = current_count - 11
        if providers_to_remove > 0
          Provider.where("name LIKE ?", "Provider Page%").limit(providers_to_remove).destroy_all
        end

        results = service.send(:search_providers_by_zone_and_category,
                               zone: "Boca del Río",
                               category_slug: "plomeria")

        # Should have exactly 11 providers now
        expect(results.to_a.size).to eq(11)

        # Should use rating-based ordering for > 10
        expect(results.to_sql).to include("AVG(reviews.rating)")
      end
    end
  end
end
