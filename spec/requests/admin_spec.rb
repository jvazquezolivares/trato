# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Panel", type: :request do
  let(:admin_username) { "admin" }
  let(:admin_password) { "secret123" }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ADMIN_USERNAME", "").and_return(admin_username)
    allow(ENV).to receive(:fetch).with("ADMIN_PASSWORD", "").and_return(admin_password)
    allow(ENV).to receive(:fetch).with("ADMIN_EMAIL", "").and_return("admin@trato.mx")
    allow(ENV).to receive(:fetch).with("TRATO_WHATSAPP_NUMBER", "").and_return("522221234567")
  end

  # Helper to simulate full admin login flow
  def admin_login!
    allow(AdminService).to receive(:valid_credentials?).and_return(true)
    allow(AdminService).to receive(:generate_confirmation_code).and_return("123456")
    allow(AdminService).to receive(:verify_confirmation_code)
      .with(code: "123456")
      .and_return({ success: true })

    post admin_login_path, params: { username: admin_username, password: admin_password }
    post admin_verify_path, params: { code: "123456" }
  end

  # --- Authentication ---

  describe "GET /admin/login" do
    it "renders the login form" do
      get admin_login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Acceso administrativo")
      expect(response.body).to include("Usuario")
      expect(response.body).to include("Contraseña")
    end

    context "when already authenticated" do
      before { admin_login! }

      it "redirects to admin dashboard" do
        get admin_login_path
        expect(response).to redirect_to(admin_path)
      end
    end
  end

  describe "POST /admin/login (authenticate)" do
    context "when credentials are valid" do
      before do
        allow(AdminService).to receive(:valid_credentials?).and_return(true)
        allow(AdminService).to receive(:generate_confirmation_code).and_return("123456")
      end

      it "renders the verification form" do
        post admin_login_path, params: { username: admin_username, password: admin_password }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Código de confirmación")
      end

      it "generates a confirmation code" do
        expect(AdminService).to receive(:generate_confirmation_code)
        post admin_login_path, params: { username: admin_username, password: admin_password }
      end
    end

    context "when credentials are invalid" do
      before do
        allow(AdminService).to receive(:valid_credentials?).and_return(false)
      end

      it "re-renders login with error" do
        post admin_login_path, params: { username: "wrong", password: "wrong" }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Credenciales incorrectas")
      end
    end
  end

  describe "POST /admin/verify" do
    context "when verification code is valid" do
      before do
        allow(AdminService).to receive(:valid_credentials?).and_return(true)
        allow(AdminService).to receive(:generate_confirmation_code).and_return("123456")
        allow(AdminService).to receive(:verify_confirmation_code)
          .with(code: "123456")
          .and_return({ success: true })

        # First authenticate to set session
        post admin_login_path, params: { username: admin_username, password: admin_password }
      end

      it "redirects to admin dashboard" do
        post admin_verify_path, params: { code: "123456" }
        expect(response).to redirect_to(admin_path)
      end
    end

    context "when verification code is invalid" do
      before do
        allow(AdminService).to receive(:valid_credentials?).and_return(true)
        allow(AdminService).to receive(:generate_confirmation_code).and_return("123456")
        allow(AdminService).to receive(:verify_confirmation_code)
          .with(code: "000000")
          .and_return({ success: false, error: :invalid })

        post admin_login_path, params: { username: admin_username, password: admin_password }
      end

      it "re-renders verify with error" do
        post admin_verify_path, params: { code: "000000" }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Código incorrecto")
      end
    end

    context "when no pending verification in session" do
      it "redirects to login" do
        post admin_verify_path, params: { code: "123456" }
        expect(response).to redirect_to(admin_login_path)
      end
    end
  end

  describe "GET /admin/logout" do
    before { admin_login! }

    it "destroys admin session and redirects to login" do
      get admin_logout_path
      expect(response).to redirect_to(admin_login_path)

      # Verify session is cleared by trying to access protected route
      get admin_path
      expect(response).to redirect_to(admin_login_path)
    end
  end

  # --- Protected routes require authentication ---

  describe "authentication protection" do
    context "when not authenticated" do
      it "redirects /admin to login" do
        get admin_path
        expect(response).to redirect_to(admin_login_path)
      end

      it "redirects /admin/providers to login" do
        get admin_providers_path
        expect(response).to redirect_to(admin_login_path)
      end

      it "redirects /admin/conversations to login" do
        get admin_conversations_path
        expect(response).to redirect_to(admin_login_path)
      end

      it "redirects /admin/finances to login" do
        get admin_finances_path
        expect(response).to redirect_to(admin_login_path)
      end
    end
  end

  # --- Dashboard ---

  describe "GET /admin (dashboard)" do
    before { admin_login! }

    it "renders the dashboard" do
      get admin_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Panel Principal")
      expect(response.body).to include("Proveedores activos")
      expect(response.body).to include("Conversaciones hoy")
      expect(response.body).to include("Costo estimado del mes")
    end
  end

  # --- Providers ---

  describe "GET /admin/providers" do
    before { admin_login! }

    let!(:provider) { create(:provider, name: "Miguel García", city: "Veracruz", active: true) }

    it "renders the providers list" do
      get admin_providers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Miguel García")
      expect(response.body).to include("Veracruz")
    end

    it "supports search filter" do
      get admin_providers_path, params: { search: "Miguel" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Miguel García")
    end

    it "supports status filter" do
      get admin_providers_path, params: { status: "active" }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Miguel García")
    end
  end

  describe "GET /admin/providers/:id" do
    before { admin_login! }

    let!(:provider) { create(:provider, name: "Miguel García") }

    it "renders the provider detail" do
      get admin_provider_path(provider)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Miguel García")
      expect(response.body).to include("Finanzas este mes")
      expect(response.body).to include(provider.short_uuid)
    end

    context "when provider does not exist" do
      it "redirects to providers list" do
        get admin_provider_path(id: -1)
        expect(response).to redirect_to(admin_providers_path)
      end
    end
  end

  # --- Conversations ---

  describe "GET /admin/conversations" do
    before { admin_login! }

    let!(:provider) { create(:provider) }
    let!(:conversation) do
      create(:conversation, provider: provider, phone: "5212219876543",
             stage: "active", last_message_at: Time.current)
    end

    it "renders the conversations list" do
      get admin_conversations_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(provider.name)
    end

    it "supports stage filter" do
      get admin_conversations_path, params: { stage: "active" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /admin/conversations/:id" do
    before { admin_login! }

    let!(:provider) { create(:provider) }
    let!(:conversation) do
      create(:conversation, provider: provider, phone: "5212219876543",
             stage: "active", last_message_at: Time.current)
    end
    let!(:message) do
      create(:message, conversation: conversation, direction: "inbound",
             body: "Hola, necesito un fontanero")
    end

    it "renders the conversation detail with messages" do
      get admin_conversation_path(conversation)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hola, necesito un fontanero")
      expect(response.body).to include(provider.name)
    end

    context "when conversation does not exist" do
      it "redirects to conversations list" do
        get admin_conversation_path(id: -1)
        expect(response).to redirect_to(admin_conversations_path)
      end
    end
  end

  # --- Finances ---

  describe "GET /admin/finances" do
    before { admin_login! }

    it "renders the finances page" do
      get admin_finances_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ingresos plataforma este mes")
      expect(response.body).to include("Costo infraestructura")
      expect(response.body).to include("Resumen por proveedor")
    end
  end
end
