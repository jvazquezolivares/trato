# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  # Sidekiq Web UI — protected with HTTP basic auth
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("ADMIN_USERNAME", "admin")) &
      ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("ADMIN_PASSWORD", "password"))
  end
  mount Sidekiq::Web => "/sidekiq"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
