# frozen_string_literal: true

# DEPRECATED: This file is no longer used.
# Sidekiq cron schedules are now configured in config/initializers/sidekiq.rb
# to avoid duplication and ensure consistency.
#
# Kept for reference only.

# Registers recurring Sidekiq-cron schedules.
# All times use Mexico City timezone (America/Mexico_City, UTC-6).
#
# Jobs registered here:
#   - MorningSummaryJob: daily at 8 am
#   - PaymentReminderJob: Fridays at 9 am (corrected from 11am)
#   - FacebookTokenRefreshJob: daily at 6 am

return if ENV["SECRET_KEY_BASE_DUMMY"] == "1"

# Rails.application.config.after_initialize do
#   Sidekiq::Cron::Job.load_from_hash(
#     "morning_summary" => {
#       "cron" => "0 8 * * * America/Mexico_City",
#       "class" => "MorningSummaryJob",
#       "description" => "Sends morning summary to active providers without a WorkDay for today"
#     },
#     "payment_reminder" => {
#       "cron" => "0 9 * * 5 America/Mexico_City",
#       "class" => "PaymentReminderJob",
#       "description" => "Sends weekly payment reminder to providers with outstanding jobs (Fridays at 9am)"
#     }
#   )
# end
