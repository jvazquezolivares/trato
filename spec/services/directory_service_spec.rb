# frozen_string_literal: true

require "rails_helper"

RSpec.describe DirectoryService do
  describe ".call" do
    let(:provider) do
      create(:provider,
             name: "Miguel García",
             city: "Veracruz",
             base_price: "$200–400 MXN",
             active: true)
    end

    let!(:primary_category) do
      create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)
    end

    context "when parsing category_city URL segment" do
      it "extracts category slug and city from valid format" do
        result = described_class.call(category_city: "fontaneros-en-veracruz")

        expect(result.category_slug).to eq("fontanero")
        expect(result.city).to eq("veracruz")
      end

      it "raises RecordNotFound for invalid format" do
        expect {
          described_class.call(category_city: "invalid-format")
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "handles multi-word cities" do
        provider.update!(city: "Boca del Río")
        result = described_class.call(category_city: "fontaneros-en-boca-del-río")

        expect(result.city).to eq("boca-del-río")
      end
    end

    context "when loading providers" do
      it "returns active providers matching category and city" do
        result = described_class.call(category_city: "fontaneros-en-veracruz")

        expect(result.providers).to include(provider)
        expect(result.total_count).to eq(1)
      end

      it "excludes inactive providers" do
        provider.update!(active: false)
        result = described_class.call(category_city: "fontaneros-en-veracruz")

        expect(result.providers).to be_empty
        expect(result.total_count).to eq(0)
      end

      it "excludes providers from other cities" do
        result = described_class.call(category_city: "fontaneros-en-puebla")

        expect(result.providers).to be_empty
      end

      it "excludes providers from other categories" do
        result = described_class.call(category_city: "electricistas-en-veracruz")

        expect(result.providers).to be_empty
      end
    end

    context "when paginating" do
      it "defaults to page 1" do
        result = described_class.call(category_city: "fontaneros-en-veracruz")

        expect(result.page).to eq(1)
      end

      it "calculates total pages correctly" do
        result = described_class.call(category_city: "fontaneros-en-veracruz")

        expect(result.total_pages).to eq(1)
      end

      it "handles invalid page numbers gracefully" do
        result = described_class.call(category_city: "fontaneros-en-veracruz", page: -1)

        expect(result.page).to eq(1)
      end
    end

    context "when filtering" do
      it "returns all providers with no filter" do
        result = described_class.call(category_city: "fontaneros-en-veracruz")

        expect(result.providers).to include(provider)
      end

      it "filters by providers with photos" do
        create(:photo, :work, provider: provider)
        result = described_class.call(category_city: "fontaneros-en-veracruz", filter: "con-fotos")

        expect(result.providers).to include(provider)
      end

      it "excludes providers without photos when filtering by photos" do
        result = described_class.call(category_city: "fontaneros-en-veracruz", filter: "con-fotos")

        expect(result.providers).to be_empty
      end
    end

    context "with category display name" do
      it "returns the titleized category name" do
        result = described_class.call(category_city: "fontaneros-en-veracruz")

        expect(result.category_display_name).to eq("Fontaneros")
      end
    end
  end
end
