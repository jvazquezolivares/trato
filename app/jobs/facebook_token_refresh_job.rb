# frozen_string_literal: true

# Refreshes Facebook OAuth tokens that are expiring within 10 days.
#
# Schedule: daily at 6 am Mexico City time (UTC-6) via Sidekiq-cron.
#
# For each active Provider with a facebook_token_expires_at within 10 days:
#   - Attempts to refresh the token via Meta Graph API
#   - On success: updates facebook_token and facebook_token_expires_at
#   - On failure: notifies the provider via WhatsApp with a new connect link
#
# Idempotency:
#   Running the job multiple times is safe — already-refreshed tokens will
#   have a new expiry date beyond the 10-day window and won't be picked up again.
class FacebookTokenRefreshJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info("[FacebookTokenRefreshJob] Starting daily token refresh check")

    FacebookOAuthService.refresh_expiring_tokens

    Rails.logger.info("[FacebookTokenRefreshJob] Completed token refresh check")
  end
end
