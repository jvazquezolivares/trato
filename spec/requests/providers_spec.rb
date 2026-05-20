# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Providers", type: :request do
  describe "GET /p/:category_city/:slug" do
    let(:provider) do
      create(:provider,
             name: "Miguel García",
             city: "Veracruz",
             service_area: "Boca del Río, Centro",
             base_price: "$200–400 MXN",
             bio: "Fontanero con experiencia en Veracruz.",
             short_uuid: "a3f8c2d1",
             slug: "fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1")
    end

    let!(:primary_category) do
      create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)
    end

    context "when the provider exists" do
      it "returns a successful response" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response).to have_http_status(:ok)
      end

      it "renders the provider name" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("Miguel García")
      end

      it "renders the primary category badge" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("Fontanero")
      end

      it "renders the city and service area" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("Veracruz")
        expect(response.body).to include("Boca del Río, Centro")
      end

      it "renders the bio" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("Fontanero con experiencia en Veracruz.")
      end

      it "renders the visit price" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("$200–400 MXN")
      end

      it "renders the CTA button with assistant_whatsapp_link" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("Contacta a Miguel")
        expect(response.body).to include("a3f8c2d1")
      end

      it "does not require authentication" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response).not_to have_http_status(:unauthorized)
        expect(response).not_to have_http_status(:redirect)
      end
    end

    context "when the provider has reviews" do
      let(:client) { create(:client, name: "Mariana López") }

      let!(:job_record) { create(:job, provider: provider, client: client, status: "paid") }

      let!(:review) do
        create(:review,
               provider: provider,
               client: client,
               job: job_record,
               rating: 5,
               comment: "Excelente trabajo, muy puntual.",
               verified: true)
      end

      it "renders the review with verified badge" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("Mariana López")
        expect(response.body).to include("Excelente trabajo, muy puntual.")
        expect(response.body).to include("Verificado por Trato")
      end

      it "renders the rating distribution" do
        get "/p/fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"

        expect(response.body).to include("Estrellas")
        expect(response.body).to include("1 reseña")
      end
    end

    context "when the provider does not exist" do
      it "returns a 404 response" do
        get "/p/fontaneros-en-veracruz/nonexistent-slug"

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
