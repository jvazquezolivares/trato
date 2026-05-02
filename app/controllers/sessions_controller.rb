# frozen_string_literal: true

# Handles provider login via WhatsApp OTP.
# No passwords — phone number + 6-digit code sent via WhatsApp.
#
# Routes:
#   GET  /login        → phone input form
#   POST /login        → generate OTP and send via WhatsApp
#   POST /login/verify → validate OTP code and create session
#   GET  /logout       → destroy session and redirect to login
class SessionsController < ApplicationController
  layout "public"

  before_action :redirect_if_authenticated, only: %i[new create]

  def new; end

  def create
    result = OtpService.generate(phone: params[:phone])

    if result[:success]
      session[:otp_phone] = OtpService.send(:normalize_phone, params[:phone])
      @masked_phone = result[:masked_phone]
      render :verify
    else
      flash.now[:alert] = "No encontramos una cuenta con ese número. " \
                          "Solo enviamos el código a números registrados en Trato."
      render :new, status: :unprocessable_entity
    end
  end

  def verify
    phone = session[:otp_phone]

    unless phone
      redirect_to login_path, alert: "Tu sesión expiró. Ingresa tu número de nuevo."
      return
    end

    result = OtpService.verify(phone: phone, code: params[:code])

    if result[:success]
      session.delete(:otp_phone)
      session[:provider_id] = result[:provider].id
      redirect_to mi_perfil_path, notice: "¡Bienvenido de vuelta!"
    else
      @masked_phone = OtpService.send(:mask_phone, phone)
      flash.now[:alert] = otp_error_message(result[:error])
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: "Sesión cerrada correctamente."
  end

  private

  def redirect_if_authenticated
    redirect_to mi_perfil_path if session[:provider_id].present?
  end

  def otp_error_message(error)
    case error
    when :expired
      "El código expiró. Solicita uno nuevo."
    when :invalid
      "Código incorrecto. Intenta de nuevo."
    when :max_attempts
      "Demasiados intentos. Solicita un nuevo código."
    else
      "Ocurrió un error. Intenta de nuevo."
    end
  end
end
