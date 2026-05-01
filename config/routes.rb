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

  # Homepage
  root "home#index"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
