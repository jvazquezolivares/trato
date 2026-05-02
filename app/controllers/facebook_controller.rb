# frozen_string_literal: true

# Handles Facebook OAuth flow for connecting a provider's Facebook page.
# Thin controller — all business logic is in FacebookOAuthService.
#
# Routes:
#   GET /connect/facebook          → validate connect_token, redirect to Facebook OAuth
#   GET /connect/facebook/callback → exchange code for tokens, save, redirect to /mi-perfil
class FacebookController < ApplicationController
  layout "public"

  # GET /connect/facebook?token={connect_token}
  # Validates the connect_token from Redis and redirects to Facebook OAuth.
  # If the token is expired, renders an error page prompting the provider
  # to request a new link via WhatsApp.
  def connect
    connect_token = params[:token]

    unless connect_token.present?
      render :token_expired, status: :bad_request
      return
    end

    result = FacebookOAuthService.validate_connect_token(token: connect_token)

    unless result[:valid]
      render :token_expired, status: :gone
      return
    end

    oauth_url = FacebookOAuthService.build_oauth_url(connect_token: connect_token)
    redirect_to oauth_url, allow_other_host: true
  end

  # GET /connect/facebook/callback?code={code}&state={connect_token}
  # Exchanges the authorization code for tokens, saves them on the provider,
  # auto-links Instagram, and redirects to /mi-perfil.
  def callback
    code = params[:code]
    connect_token = params[:state]

    unless code.present? && connect_token.present?
      redirect_to login_path, alert: "No se pudo completar la conexión con Facebook."
      return
    end

    result = FacebookOAuthService.exchange_code(code: code, connect_token: connect_token)

    if result[:success]
      session[:provider_id] = result[:provider].id
      redirect_to mi_perfil_path, notice: "¡Facebook conectado correctamente! 🎉"
    else
      redirect_to login_path, alert: result[:error] || "Error al conectar Facebook."
    end
  end
end
