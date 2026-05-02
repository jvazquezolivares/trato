class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  # Ensures the current request has an authenticated provider session.
  # Use as: before_action :require_provider_session
  def require_provider_session
    return if current_provider

    redirect_to login_path, alert: "Inicia sesión para continuar."
  end

  # Returns the currently authenticated Provider, or nil.
  def current_provider
    return @current_provider if defined?(@current_provider)

    @current_provider = session[:provider_id] && Provider.find_by(id: session[:provider_id])
  end

  helper_method :current_provider
end
