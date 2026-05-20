# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Directories", type: :request do
  describe "GET /p/:category_city" do
    let(:provider) do
      create(:provider,
             name: "Miguel García",
             city: "Veracruz",
             base_price: "$200–400 MXN",
             bio: "Fontanero con experiencia en Veracruz.",
             short_uuid: "a3f8c2d1",
             slug: "fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1",
             active: true)
    end

    let!(:primary_category) do
      create(:provider_category, provider: provider, name: "Fontanero", slug: "fontanero", primary: true)
    end

    context "when providers exist for the category and city" do
      it "returns a successful response" do
        get "/p/fontaneros-en-veracruz"

        expect(response).to have_http_status(:ok)
      end

      it "renders the H1 heading with category and city" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Fontaneros en Veracruz")
      end

      it "renders the verified provider count" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("1 profesional verificado listo")
      end

      it "renders the provider name in the card" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Miguel García")
      end

      it "renders the provider price" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("$300")
      end

      it "renders the category in the card" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Fontanero")
      end

      it "renders the CTA button" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Contactar")
      end

      it "renders the verified badge" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Verificado")
      end

      it "does not require authentication" do
        get "/p/fontaneros-en-veracruz"

        expect(response).not_to have_http_status(:unauthorized)
        expect(response).not_to have_http_status(:redirect)
      end
    end

    context "when provider has a work photo" do
      let!(:work_photo) do
        create(:photo, :work, provider: provider, caption: "Instalación eléctrica")
      end

      it "renders the work photo as the main card image" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include(work_photo.url)
      end
    end

    context "when provider has a profile photo" do
      let!(:profile_photo) do
        create(:photo, :profile, provider: provider)
      end

      it "renders the circular profile photo overlay" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include(profile_photo.url)
      end
    end

    context "when provider has no work photo" do
      it "renders the placeholder" do
        get "/p/fontaneros-en-veracruz"

        # The placeholder uses a house SVG icon on light gray background
        expect(response.body).to include("bg-[#F1F5F9]")
      end
    end

    context "when provider has reviews" do
      let(:client) { create(:client, name: "Mariana López") }
      let!(:job_record) { create(:job, provider: provider, client: client, status: "paid") }
      let!(:review) { create(:review, provider: provider, client: client, job: job_record, rating: 5, verified: true) }

      it "renders the rating badge on the card" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("5.0")
      end
    end

    context "when multiple providers exist" do
      let(:provider2) do
        create(:provider,
               name: "Carlos Pérez",
               city: "Veracruz",
               base_price: "$400–600 MXN",
               short_uuid: "b4e9d3f2",
               slug: "fontaneros-en-veracruz/carlos-perez-fontanero-b4e9d3f2",
               active: true)
      end

      let!(:category2) do
        create(:provider_category, provider: provider2, name: "Fontanero", slug: "fontanero", primary: true)
      end

      it "renders both providers" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Miguel García")
        expect(response.body).to include("Carlos Pérez")
      end

      it "shows the correct count" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("2 profesionales verificados listos")
      end
    end

    context "when no providers match the category and city" do
      it "renders the empty state" do
        get "/p/electricistas-en-puebla"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No encontramos técnicos para esa búsqueda")
      end
    end

    context "when the URL format is invalid" do
      it "returns a 404 response" do
        get "/p/invalid-format"

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when inactive providers exist" do
      before { provider.update!(active: false) }

      it "does not include inactive providers" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).not_to include("Miguel García")
        expect(response.body).to include("No encontramos técnicos")
      end
    end

    context "when filter is applied" do
      it "accepts the filter parameter" do
        get "/p/fontaneros-en-veracruz", params: { filter: "mejor-calificados" }

        expect(response).to have_http_status(:ok)
      end
    end

    context "when pagination is needed" do
      it "accepts the page parameter" do
        get "/p/fontaneros-en-veracruz", params: { page: 1 }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with the filter bar" do
      it "renders filter chips" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Todos")
        expect(response.body).to include("Mejor calificados")
        expect(response.body).to include("Con fotos de trabajos")
        expect(response.body).to include("Precio: Bajo a Alto")
      end
    end

    context "with breadcrumbs" do
      it "renders the breadcrumb navigation" do
        get "/p/fontaneros-en-veracruz"

        expect(response.body).to include("Trato")
        expect(response.body).to include("Veracruz")
        expect(response.body).to include("Fontaneros")
      end
    end
  end
end
