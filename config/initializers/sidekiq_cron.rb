# frozen_string_literal: true

# Registers recurring Sidekiq-cron schedules.
# All times use Mexico City timezone (America/Mexico_City, UTC-6).
#
# Jobs registered here:
#   - MorningSummaryJob: daily at 8 am
#   - PaymentReminderJob: Fridays at 11 am
#   - FacebookTokenRefreshJob: daily at 6 am (pending implementation)

return if ENV["SECRET_KEY_BASE_DUMMY"] == "1"

Rails.application.config.after_initialize do
  Sidekiq::Cron::Job.load_from_hash(
    "morning_summary" => {
      "cron" => "0 8 * * * America/Mexico_City",
      "class" => "MorningSummaryJob",
      "description" => "Sends morning summary to active providers without a WorkDay for today"
    },
    "payment_reminder" => {
      "cron" => "0 11 * * 5 America/Mexico_City",
      "class" => "PaymentReminderJob",
      "description" => "Sends weekly payment reminder to providers with outstanding jobs (Fridays at 11am)"
    }
  )
end
