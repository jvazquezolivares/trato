# frozen_string_literal: true

# Admin panel controller — monitors providers, conversations, and finances.
#
# Authentication flow:
#   1. GET  /admin/login  → username + password form
#   2. POST /admin/login  → validate credentials, generate confirmation code, send to ADMIN_EMAIL
#   3. POST /admin/verify → validate confirmation code, create admin session
#
# All /admin routes (except login/verify) are protected with require_admin_session.
# Business logic is delegated to AdminService.
#
# Routes:
#   GET  /admin           → dashboard (default)
#   GET  /admin/login     → login form
#   POST /admin/login     → submit credentials
#   POST /admin/verify    → verify confirmation code
#   GET  /admin/providers → providers list
#   GET  /admin/providers/:id → provider detail
#   GET  /admin/conversations → conversations list
#   GET  /admin/conversations/:id → conversation detail
#   GET  /admin/finances  → financial overview
#   GET  /admin/logout    → destroy admin session
class AdminController < ApplicationController
  layout "admin"

  skip_before_action :verify_authenticity_token, only: [] # all actions use CSRF
  before_action :require_admin_session, except: %i[login authenticate verify]
  before_action :redirect_if_admin_authenticated, only: %i[login]

  # --- Authentication ---

  # GET /admin/login
  def login; end

  # POST /admin/login — validate username + password, then send confirmation code
  def authenticate
    unless AdminService.valid_credentials?(username: params[:username], password: params[:password])
      flash.now[:alert] = "Credenciales incorrectas."
      render :login, status: :unprocessable_entity
      return
    end

    AdminService.generate_confirmation_code
    session[:admin_pending_verification] = true
    render :verify
  end

  # POST /admin/verify — validate confirmation code
  def verify
    unless session[:admin_pending_verification]
      redirect_to admin_login_path
      return
    end

    result = AdminService.verify_confirmation_code(code: params[:code])

    if result[:success]
      session.delete(:admin_pending_verification)
      session[:admin_authenticated] = true
      redirect_to admin_path, notice: "Bienvenido al panel de administración."
    else
      flash.now[:alert] = verification_error_message(result[:error])
      render :verify, status: :unprocessable_entity
    end
  end

  # GET /admin/logout
  def logout
    session.delete(:admin_authenticated)
    session.delete(:admin_pending_verification)
    redirect_to admin_login_path, notice: "Sesión de administrador cerrada."
  end

  # --- Dashboard ---

  # GET /admin
  def dashboard
    @stats = AdminService.dashboard_stats
    @recent_activity = AdminService.recent_activity(limit: 8)
    @provider_breakdown = AdminService.provider_status_breakdown
  end

  # --- Providers ---

  # GET /admin/providers
  def providers
    @providers = AdminService.providers_list(
      status: params[:status],
      city: params[:city],
      search: params[:search]
    )
    @cities = Provider.distinct.pluck(:city).compact.sort
  end

  # GET /admin/providers/:id
  def provider_detail
    @detail = AdminService.provider_detail(params[:id])

    unless @detail
      redirect_to admin_providers_path, alert: "Proveedor no encontrado."
      return
    end

    @provider = @detail[:provider]
    @financial = @detail[:financial_summary]
    @recent_conversations = @detail[:recent_conversations]
    @recent_jobs = @detail[:recent_jobs]
  end

  # --- Conversations ---

  # GET /admin/conversations
  def conversations
    @conversations = AdminService.conversations_list(
      provider_id: params[:provider_id],
      stage: params[:stage],
      date_from: params[:date_from],
      date_to: params[:date_to]
    )
    @providers_for_filter = Provider.order(:name).pluck(:name, :id)
    @stages = Conversation.distinct.pluck(:stage).compact.sort
  end

  # GET /admin/conversations/:id
  def conversation_detail
    @detail = AdminService.conversation_detail(params[:id])

    unless @detail
      redirect_to admin_conversations_path, alert: "Conversación no encontrada."
      return
    end

    @conversation = @detail[:conversation]
    @messages = @detail[:messages]
    @provider = @detail[:provider]
    @client = @detail[:client]
  end

  # --- Finances ---

  # GET /admin/finances
  def finances
    @summary = AdminService.financial_summary
    @providers_financial = AdminService.providers_financial_list
  end

  private

  def require_admin_session
    return if session[:admin_authenticated]

    redirect_to admin_login_path, alert: "Acceso restringido. Inicia sesión como administrador."
  end

  def redirect_if_admin_authenticated
    redirect_to admin_path if session[:admin_authenticated]
  end

  def verification_error_message(error)
    case error
    when :expired
      "El código expiró. Inicia sesión de nuevo."
    when :invalid
      "Código incorrecto. Intenta de nuevo."
    when :max_attempts
      "Demasiados intentos. Inicia sesión de nuevo."
    else
      "Ocurrió un error. Intenta de nuevo."
    end
  end
end
