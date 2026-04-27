# frozen_string_literal: true

# Shared Redis connection for application-level state (onboarding, tokens, etc.).
# Sidekiq manages its own connection pool separately in sidekiq.rb.
REDIS = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
