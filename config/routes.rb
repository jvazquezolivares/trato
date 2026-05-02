# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  # Sidekiq Web UI — protected with HTTP basic auth
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("ADMIN_USERNAME", "admin")) &
      ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("ADMIN_PASSWORD", "password"))
  end
  mount Sidekiq::Web => "/sidekiq"

  # WhatsApp webhook — Meta Cloud API verification and incoming messages
  get "/webhooks/whatsapp", to: "webhooks#verify"
  post "/webhooks/whatsapp", to: "webhooks#receive"

  # Public category directory page — SEO-friendly URL, no auth required
  get "/p/:category_city", to: "directories#show", as: :category_directory

  # Public provider profile page — SEO-friendly URL, no auth required
  get "/p/:category_city/:slug", to: "providers#show", as: :provider_profile

  # Provider login — WhatsApp OTP authentication (no passwords)
  get "/login", to: "sessions#new", as: :login
  post "/login", to: "sessions#create"
  post "/login/verify", to: "sessions#verify", as: :login_verify
  get "/logout", to: "sessions#destroy", as: :logout

  # Provider panel — requires authenticated session
  get "/mi-perfil", to: "provider_panel#show", as: :mi_perfil
  patch "/mi-perfil", to: "provider_panel#update"
  get "/mi-perfil/tab/:tab_name", to: "provider_panel#tab", as: :mi_perfil_tab
  post "/mi-perfil/photos", to: "provider_panel#upload_photo", as: :mi_perfil_photos
  delete "/mi-perfil/photos/:id", to: "provider_panel#destroy_photo", as: :mi_perfil_photo
  patch "/mi-perfil/photos/reorder", to: "provider_panel#reorder_photos", as: :mi_perfil_photos_reorder

  # Homepage
  root "home#index"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
