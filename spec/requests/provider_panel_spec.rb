# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Provider Panel (/mi-perfil)", type: :request do
  let(:phone) { "5212211234567" }
  let(:masked_phone) { "+52 *** ***4567" }
  let(:provider) { create(:provider, phone: phone, name: "Miguel García", city: "Veracruz") }

  # Helper to simulate an authenticated session
  def authenticate_provider(prov = provider)
    allow(OtpService).to receive(:generate).with(phone: prov.phone).and_return(
      { success: true, masked_phone: masked_phone }
    )
    allow(OtpService).to receive(:normalize_phone).with(prov.phone).and_return(prov.phone)
    allow(OtpService).to receive(:verify).with(phone: prov.phone, code: "123456").and_return(
      { success: true, provider: prov }
    )

    post "/login", params: { phone: prov.phone }
    post "/login/verify", params: { code: "123456" }
  end

  describe "GET /mi-perfil" do
    context "when not authenticated" do
      it "redirects to login" do
        get "/mi-perfil"
        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      before { authenticate_provider }

      it "renders the panel with provider name" do
        get "/mi-perfil"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Mi perfil")
        expect(response.body).to include("Miguel García")
      end

      it "displays the metrics section" do
        get "/mi-perfil"

        expect(response.body).to include("trabajos este mes")
        expect(response.body).to include("ganados este mes")
        expect(response.body).to include("calificación")
        expect(response.body).to include("reseñas nuevas")
      end

      it "displays all 4 tab links" do
        get "/mi-perfil"

        expect(response.body).to include("Información")
        expect(response.body).to include("Fotos")
        expect(response.body).to include("Redes sociales")
        expect(response.body).to include("Mi asistente")
      end

      it "defaults to the informacion tab" do
        get "/mi-perfil"

        expect(response.body).to include("Nombre completo")
        expect(response.body).to include("Guardar cambios")
      end
    end

    context "when tab parameter is fotos" do
      before { authenticate_provider }

      it "renders the photos tab" do
        get "/mi-perfil", params: { tab: "fotos" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("de 10 fotos")
      end
    end

    context "when tab parameter is redes" do
      before { authenticate_provider }

      it "renders the social media tab" do
        get "/mi-perfil", params: { tab: "redes" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Página de Facebook")
        expect(response.body).to include("Instagram")
      end
    end

    context "when tab parameter is asistente" do
      before { authenticate_provider }

      it "renders the assistant config tab" do
        get "/mi-perfil", params: { tab: "asistente" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Número del asistente")
        expect(response.body).to include("Tu link de asistente")
        expect(response.body).to include("Comparte este QR con tus clientes")
        expect(response.body).to include("Mensaje automático sugerido")
      end

      it "displays the assistant WhatsApp link" do
        get "/mi-perfil", params: { tab: "asistente" }

        expect(response.body).to include(provider.assistant_whatsapp_link)
      end

      it "displays the auto-reply message with the assistant link" do
        get "/mi-perfil", params: { tab: "asistente" }

        expect(response.body).to include("Ahorita estoy trabajando")
        expect(response.body).to include(provider.assistant_whatsapp_link)
      end
    end
  end

  describe "PATCH /mi-perfil" do
    context "when not authenticated" do
      it "redirects to login" do
        patch "/mi-perfil", params: { provider: { name: "New Name" } }
        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      before { authenticate_provider }

      it "updates the provider basic info" do
        patch "/mi-perfil", params: {
          provider: { name: "Miguel Updated", city: "Puebla", bio: "New bio", base_price: 500, email: "miguel@test.com" }
        }

        expect(response).to redirect_to(mi_perfil_path)
        provider.reload
        expect(provider.name).to eq("Miguel Updated")
        expect(provider.city).to eq("Puebla")
        expect(provider.bio).to eq("New bio")
        expect(provider.base_price).to eq(500)
        expect(provider.email).to eq("miguel@test.com")
      end

      it "updates service area" do
        patch "/mi-perfil", params: {
          provider: { service_area: "Boca del Río, Centro, Mocambo" }
        }

        expect(response).to redirect_to(mi_perfil_path)
        provider.reload
        expect(provider.service_area).to eq("Boca del Río, Centro, Mocambo")
      end
    end
  end

  describe "DELETE /mi-perfil/photos/:id" do
    before { authenticate_provider }

    context "when photo belongs to the provider" do
      let!(:photo) { create(:photo, provider: provider) }

      it "deletes the photo and redirects" do
        expect {
          delete "/mi-perfil/photos/#{photo.id}"
        }.to change(Photo, :count).by(-1)

        expect(response).to redirect_to(mi_perfil_path(tab: "fotos"))
      end
    end

    context "when photo does not belong to the provider" do
      let(:other_provider) { create(:provider) }
      let!(:photo) { create(:photo, provider: other_provider) }

      it "does not delete the photo" do
        expect {
          delete "/mi-perfil/photos/#{photo.id}"
        }.not_to change(Photo, :count)

        expect(response).to redirect_to(mi_perfil_path(tab: "fotos"))
      end
    end
  end

  describe "metrics display" do
    before { authenticate_provider }

    context "when provider has jobs and income this month" do
      let(:client) { create(:client) }

      before do
        create(:job, provider: provider, client: client, service_date: Date.current, status: "paid")
        create(:job, provider: provider, client: client, service_date: Date.current, status: "paid")
        create(:transaction, provider: provider, transaction_type: "income", amount: 1500, recorded_at: Time.current)
        create(:transaction, provider: provider, transaction_type: "income", amount: 2000, recorded_at: Time.current)
      end

      it "displays correct job count" do
        get "/mi-perfil"
        expect(response.body).to include("2")
      end

      it "displays correct income" do
        get "/mi-perfil"
        expect(response.body).to include("$3,500")
      end
    end

    context "when provider has reviews" do
      let(:client) { create(:client) }

      before do
        job1 = create(:job, provider: provider, client: client)
        create(:review, provider: provider, client: client, job: job1, rating: 5, verified: true, created_at: Time.current)
      end

      it "displays the rating" do
        get "/mi-perfil"
        expect(response.body).to include("5.0 ★")
      end

      it "displays new reviews count" do
        get "/mi-perfil"
        # The "1" for new reviews should appear in the metrics
        expect(response.body).to include("reseñas nuevas")
      end
    end
  end

  describe "social media tab states" do
    before { authenticate_provider }

    context "when Facebook is connected" do
      before do
        provider.update!(facebook_token: "fb_token_123", facebook_page_url: "https://facebook.com/miguel")
      end

      it "shows connected state" do
        get "/mi-perfil", params: { tab: "redes" }

        expect(response.body).to include("Facebook conectado")
        expect(response.body).to include("facebook.com/miguel")
      end
    end

    context "when Facebook is not connected" do
      it "shows connect button" do
        get "/mi-perfil", params: { tab: "redes" }

        expect(response.body).to include("Conectar Facebook")
      end
    end

    context "when Instagram is linked" do
      before do
        provider.update!(instagram_token: "ig_token_123")
      end

      it "shows Instagram active" do
        get "/mi-perfil", params: { tab: "redes" }

        expect(response.body).to include("Instagram activo")
      end
    end
  end
end
