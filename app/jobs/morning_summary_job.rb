# frozen_string_literal: true

# Sends a morning summary prompt to every active Provider who has not yet
# reported their WorkDay for today.
#
# Schedule: daily at 8 am Mexico City time (UTC-6) via Sidekiq-cron.
#
# Idempotency:
#   The job checks for an existing WorkDay for today before sending.
#   If a WorkDay already exists (even from a previous run), the provider
#   is skipped. Running the job twice on the same day produces no
#   duplicate messages.
#
# The morning summary includes all pending Task records from the previous
# day. The tone is warm and colloquial Mexican Spanish — never scolds
# the provider for not reporting availability.
class MorningSummaryJob < ApplicationJob
  queue_as :default

  MEXICO_CITY_TZ = "America/Mexico_City"

  def perform
    today = current_date_in_mexico_city
    yesterday = today - 1.day

    active_providers_without_work_day(today).find_each do |provider|
      pending_tasks = pending_tasks_for(provider, yesterday)
      message = build_morning_message(provider, pending_tasks)

      WhatsAppService.send_message(to: provider.phone, message: message)

      Rails.logger.info(
        "[MorningSummaryJob] Sent morning summary to #{provider.name} " \
        "(#{provider.phone}) — #{pending_tasks.size} pending tasks"
      )
    end
  end

  private

  # Returns today's date in Mexico City timezone
  def current_date_in_mexico_city
    Time.current.in_time_zone(MEXICO_CITY_TZ).to_date
  end

  # Returns active providers who have no WorkDay record for the given date.
  # Uses a LEFT JOIN to avoid N+1 queries.
  def active_providers_without_work_day(date)
    Provider
      .where(active: true)
      .where.not(
        id: WorkDay.where(date: date).select(:provider_id)
      )
  end

  # Returns pending tasks for a provider from the given date or earlier
  def pending_tasks_for(provider, date)
    provider.tasks.where(status: "pending").where("created_at <= ?", date.end_of_day)
  end

  # Builds the morning message in warm, colloquial Mexican Spanish.
  # Max 2 emojis per message, never scolds for not reporting.
  # Instructs the provider to report task completions and new tasks.
  def build_morning_message(provider, pending_tasks)
    greeting = "Buenos días #{provider.name} ☀️"

    if pending_tasks.any?
      task_list = pending_tasks.map { |task| "• #{task.description}" }.join("\n")

      "#{greeting}\n" \
        "Tienes #{pending_tasks.size} #{pending_tasks.size == 1 ? 'pendiente' : 'pendientes'} de ayer:\n" \
        "#{task_list}\n" \
        "Indícame cuando termines tus pendientes para que pueda tacharlos de tu lista de tareas. " \
        "¿Tienes más pendientes para hoy? Menciónamelos para que pueda registrarlos y llevar un mejor control 📋"
    else
      "#{greeting}\n" \
        "¿Tienes pendientes para hoy? " \
        "Menciónamelos para que pueda registrarlos y llevar un mejor control 📋"
    end
  end
end
