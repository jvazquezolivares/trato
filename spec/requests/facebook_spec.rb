# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Facebook OAuth", type: :request do
  let(:connect_token) { "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4" }
  let(:provider) do
    instance_double(Provider, id: 42, name: "Miguel García", phone: "5212211234567")
  end

  describe "GET /connect/facebook" do
    context "when no token parameter is provided" do
      it "renders the token_expired page with 400 status" do
        get "/connect/facebook"

        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include("Enlace expirado")
      end
    end

    context "when the connect_token is valid" do
      before do
        allow(FacebookOAuthService).to receive(:validate_connect_token)
          .with(token: connect_token)
          .and_return({ valid: true, provider: provider })

        allow(FacebookOAuthService).to receive(:build_oauth_url)
          .with(connect_token: connect_token)
          .and_return("https://www.facebook.com/v19.0/dialog/oauth?client_id=123")
      end

      it "redirects to the Facebook OAuth URL" do
        get "/connect/facebook", params: { token: connect_token }

        expect(response).to have_http_status(:redirect)
        expect(response.location).to start_with("https://www.facebook.com/v19.0/dialog/oauth")
      end
    end

    context "when the connect_token is expired" do
      before do
        allow(FacebookOAuthService).to receive(:validate_connect_token)
          .with(token: connect_token)
          .and_return({ valid: false, error: :expired })
      end

      it "renders the token_expired page with 410 status" do
        get "/connect/facebook", params: { token: connect_token }

        expect(response).to have_http_status(:gone)
        expect(response.body).to include("Enlace expirado")
      end

      it "shows instructions to request a new link" do
        get "/connect/facebook", params: { token: connect_token }

        expect(response.body).to include("nuevo enlace")
      end

      it "includes a WhatsApp link to the assistant" do
        get "/connect/facebook", params: { token: connect_token }

        expect(response.body).to include("wa.me")
      end
    end
  end

  describe "GET /connect/facebook/callback" do
    let(:auth_code) { "auth_code_from_facebook" }

    context "when code or state is missing" do
      it "redirects to login with an alert when code is missing" do
        get "/connect/facebook/callback", params: { state: connect_token }

        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("No se pudo completar")
      end

      it "redirects to login with an alert when state is missing" do
        get "/connect/facebook/callback", params: { code: auth_code }

        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to include("No se pudo completar")
      end
    end

    context "when the token exchange succeeds" do
      before do
        allow(FacebookOAuthService).to receive(:exchange_code)
          .with(code: auth_code, connect_token: connect_token)
          .and_return({ success: true, provider: provider })
      end

      it "sets the provider session" do
        get "/connect/facebook/callback", params: { code: auth_code, state: connect_token }

        expect(session[:provider_id]).to eq(42)
      end

      it "redirects to /mi-perfil with a success notice" do
        get "/connect/facebook/callback", params: { code: auth_code, state: connect_token }

        expect(response).to redirect_to(mi_perfil_path)
        expect(flash[:notice]).to include("Facebook conectado")
      end
    end

    context "when the token exchange fails" do
      before do
        allow(FacebookOAuthService).to receive(:exchange_code)
          .with(code: auth_code, connect_token: connect_token)
          .and_return({ success: false, error: "Token expirado" })
      end

      it "redirects to login with the error message" do
        get "/connect/facebook/callback", params: { code: auth_code, state: connect_token }

        expect(response).to redirect_to(login_path)
        expect(flash[:alert]).to eq("Token expirado")
      end
    end
  end
end
