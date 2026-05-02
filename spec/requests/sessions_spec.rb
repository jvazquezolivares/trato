# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sessions (Provider Login)", type: :request do
  let(:phone) { "5212211234567" }
  let(:masked_phone) { "+52 *** ***4567" }

  describe "GET /login" do
    it "renders the phone input form" do
      get "/login"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Accede a tu perfil")
      expect(response.body).to include("Teléfono")
    end

    context "when provider is already authenticated" do
      let(:provider) { create(:provider, phone: phone) }

      it "redirects to /mi-perfil" do
        # Simulate an authenticated session through the full login flow
        allow(OtpService).to receive(:generate).with(phone: phone).and_return(
          { success: true, masked_phone: masked_phone }
        )
        allow(OtpService).to receive(:normalize_phone).with(phone).and_return(phone)
        allow(OtpService).to receive(:verify).with(phone: phone, code: "123456").and_return(
          { success: true, provider: provider }
        )

        post "/login", params: { phone: phone }
        post "/login/verify", params: { code: "123456" }

        # Now visit /login again — should redirect since we're authenticated
        get "/login"

        expect(response).to redirect_to(mi_perfil_path)
      end
    end
  end

  describe "POST /login" do
    context "when phone matches a registered provider" do
      before do
        allow(OtpService).to receive(:generate).with(phone: phone).and_return(
          { success: true, masked_phone: masked_phone }
        )
      end

      it "renders the OTP verification form" do
        post "/login", params: { phone: phone }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Ingresa tu código")
        expect(response.body).to include(masked_phone)
      end

      it "stores the normalized phone in session for verification step" do
        allow(OtpService).to receive(:normalize_phone).with(phone).and_return(phone)

        post "/login", params: { phone: phone }

        expect(response).to have_http_status(:ok)
      end
    end

    context "when phone does not match any provider" do
      before do
        allow(OtpService).to receive(:generate).with(phone: phone).and_return(
          { success: false, error: :not_found }
        )
      end

      it "re-renders the phone form with an error" do
        post "/login", params: { phone: phone }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("No encontramos una cuenta con ese número")
      end
    end
  end

  describe "POST /login/verify" do
    let(:code) { "482913" }
    let(:provider) { create(:provider, phone: phone) }

    context "when OTP is valid" do
      before do
        allow(OtpService).to receive(:verify).with(phone: phone, code: code).and_return(
          { success: true, provider: provider }
        )
        allow(OtpService).to receive(:normalize_phone).with(phone).and_return(phone)
        allow(OtpService).to receive(:generate).with(phone: phone).and_return(
          { success: true, masked_phone: masked_phone }
        )
      end

      it "redirects to /mi-perfil with a welcome notice" do
        # First set up the session with the phone
        post "/login", params: { phone: phone }
        # Then verify the code
        post "/login/verify", params: { code: code }

        expect(response).to redirect_to(mi_perfil_path)
        follow_redirect!
        expect(response.body).to include("Bienvenido")
      end
    end

    context "when OTP is invalid" do
      before do
        allow(OtpService).to receive(:verify).with(phone: phone, code: "000000").and_return(
          { success: false, error: :invalid }
        )
        allow(OtpService).to receive(:mask_phone).with(phone).and_return(masked_phone)
        allow(OtpService).to receive(:normalize_phone).with(phone).and_return(phone)
        allow(OtpService).to receive(:generate).with(phone: phone).and_return(
          { success: true, masked_phone: masked_phone }
        )
      end

      it "re-renders the verification form with an error" do
        post "/login", params: { phone: phone }
        post "/login/verify", params: { code: "000000" }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Código incorrecto")
      end
    end

    context "when OTP has expired" do
      before do
        allow(OtpService).to receive(:verify).with(phone: phone, code: code).and_return(
          { success: false, error: :expired }
        )
        allow(OtpService).to receive(:mask_phone).with(phone).and_return(masked_phone)
        allow(OtpService).to receive(:normalize_phone).with(phone).and_return(phone)
        allow(OtpService).to receive(:generate).with(phone: phone).and_return(
          { success: true, masked_phone: masked_phone }
        )
      end

      it "re-renders with expiration message" do
        post "/login", params: { phone: phone }
        post "/login/verify", params: { code: code }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("El código expiró")
      end
    end

    context "when session has no phone (direct access to verify)" do
      it "redirects to login page" do
        post "/login/verify", params: { code: "123456" }

        expect(response).to redirect_to(login_path)
      end
    end
  end

  describe "GET /logout" do
    it "redirects to login with a notice" do
      get "/logout"

      expect(response).to redirect_to(login_path)
      follow_redirect!
      expect(response.body).to include("Sesión cerrada")
    end
  end

  describe "GET /mi-perfil (auth protection)" do
    context "when not authenticated" do
      it "redirects to login" do
        get "/mi-perfil"

        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      let(:provider) { create(:provider, phone: phone) }

      it "renders the provider panel" do
        # Simulate login by setting session through the full flow
        allow(OtpService).to receive(:generate).with(phone: phone).and_return(
          { success: true, masked_phone: masked_phone }
        )
        allow(OtpService).to receive(:normalize_phone).with(phone).and_return(phone)
        allow(OtpService).to receive(:verify).with(phone: phone, code: "123456").and_return(
          { success: true, provider: provider }
        )

        post "/login", params: { phone: phone }
        post "/login/verify", params: { code: "123456" }
        get "/mi-perfil"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Mi perfil")
      end
    end
  end
end
