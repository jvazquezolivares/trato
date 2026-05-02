# frozen_string_literal: true

# Sends a weekly payment reminder to every Provider who has outstanding
# Job records (status: pending or partial).
#
# Schedule: every Friday at 9 am Mexico City time (America/Mexico_City)
# via Sidekiq-cron.
#
# Idempotency:
#   The job only reads Job records and sends messages — it does not
#   modify any records. Running it twice on the same Friday sends
#   duplicate messages, but since it's cron-scheduled to run once,
#   this is acceptable for MVP.
#
# Outstanding amount calculation:
#   For each provider, find Jobs with status "pending" or "partial",
#   group by client, and sum (amount - paid_amount) per client.
class PaymentReminderJob < ApplicationJob
  queue_as :default

  OUTSTANDING_STATUSES = %w[pending partial].freeze

  def perform
    providers_with_outstanding_jobs.find_each do |provider|
      outstanding_by_client = outstanding_amounts_grouped_by_client(provider)
      next if outstanding_by_client.empty?

      message = build_reminder_message(provider, outstanding_by_client)
      WhatsAppService.send_message(to: provider.phone, message: message)

      Rails.logger.info(
        "[PaymentReminderJob] Sent payment reminder to #{provider.name} " \
        "(#{provider.phone}) — #{outstanding_by_client.size} clients with outstanding balance"
      )
    end
  end

  private

  # Returns providers who have at least one outstanding job.
  # Uses a subquery to avoid loading all providers.
  def providers_with_outstanding_jobs
    Provider
      .where(active: true)
      .where(id: Job.where(status: OUTSTANDING_STATUSES).select(:provider_id))
  end

  # Groups outstanding jobs by client and calculates the total owed per client.
  # Uses eager_load to avoid N+1 queries on client association.
  #
  # Returns an array of hashes: [{ client_name:, total_outstanding:, job_count: }]
  def outstanding_amounts_grouped_by_client(provider)
    outstanding_jobs = provider
      .jobs
      .where(status: OUTSTANDING_STATUSES)
      .eager_load(:client)

    outstanding_jobs
      .group_by(&:client)
      .map do |client, jobs|
        total_outstanding = jobs.sum { |job| job.amount - job.paid_amount }

        {
          client_name: client&.name || "Cliente sin nombre",
          total_outstanding: total_outstanding,
          job_count: jobs.size
        }
      end
      .select { |entry| entry[:total_outstanding].positive? }
  end

  # Builds the payment reminder message in warm, colloquial Mexican Spanish.
  # Max 2 emojis, 5-6 lines.
  def build_reminder_message(provider, outstanding_by_client)
    total = outstanding_by_client.sum { |entry| entry[:total_outstanding] }

    client_lines = outstanding_by_client.map do |entry|
      "• #{entry[:client_name]}: $#{'%.2f' % entry[:total_outstanding]}"
    end

    "Hola #{provider.name} 💰\n" \
      "Tienes cobros pendientes por $#{'%.2f' % total}:\n" \
      "#{client_lines.join("\n")}\n" \
      "¿Quieres que les mande recordatorio de pago? 📋"
  end
end
