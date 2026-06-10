# frozen_string_literal: true

return if ENV["SECRET_KEY_BASE_DUMMY"] == "1"

Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  config.on(:startup) do
    schedule = {
      "morning_summary_job" => {
        "cron" => "0 8 * * * America/Mexico_City",
        "class" => "MorningSummaryJob",
        "description" => "Daily 8am CDMX — morning summary for providers without WorkDay"
      },
      "payment_reminder_job" => {
        "cron" => "0 9 * * 5 America/Mexico_City",
        "class" => "PaymentReminderJob",
        "description" => "Every Friday 9am CDMX — payment reminders for outstanding jobs"
      },
      "facebook_token_refresh_job" => {
        "cron" => "0 6 * * * America/Mexico_City",
        "class" => "FacebookTokenRefreshJob",
        "description" => "Daily 6am CDMX — refresh Facebook tokens expiring within 10 days"
      }
    }

    Rails.logger.info("[Sidekiq] Loading cron schedules: #{schedule.keys.join(', ')}")
    Sidekiq::Cron::Job.load_from_hash!(schedule)
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end
