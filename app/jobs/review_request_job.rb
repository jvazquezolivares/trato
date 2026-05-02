# frozen_string_literal: true

# Sends a review request to a Client after a completed Job.
#
# Scheduling logic:
#   - Minimum 24-hour delay after job completion
#   - Delivered at 11:00 am Mexico City time (UTC-6) on the first eligible day
#     AFTER the 24-hour window — never at the exact 24-hour mark
#
# Attempt tracking:
#   - Max 3 delivery attempts per Job (tracked via `review_attempts` column)
#   - After 3 attempts, stops without further retries
#
# Guard clauses:
#   - Skips silently if Job not found
#   - Skips silently if client has no phone on record
#   - Skips silently if review already sent (`review_sent` is true)
#   - Skips silently if max attempts reached
class ReviewRequestJob < ApplicationJob
  queue_as :default

  # Mexico City timezone identifier for ActiveSupport::TimeZone
  MEXICO_CITY_TZ = "America/Mexico_City"

  # Hour of day (in Mexico City time) when review requests are delivered
  DELIVERY_HOUR = 11

  # Maximum number of review request attempts per Job
  MAX_ATTEMPTS = 3

  # Calculates the delivery time for a review request.
  #
  # Rules:
  #   1. Must be at least 24 hours after `completed_at`
  #   2. Must be at 11:00 am Mexico City time
  #   3. Must NOT be at the exact 24-hour mark — always the NEXT eligible 11am
  #
  # @param completed_at [Time, DateTime] the timestamp when the job was completed
  # @return [ActiveSupport::TimeWithZone] the scheduled delivery time
  def self.calculate_delivery_time(completed_at)
    mexico_city = ActiveSupport::TimeZone[MEXICO_CITY_TZ]
    completed_in_cdmx = completed_at.in_time_zone(mexico_city)

    # The earliest moment we could deliver is strictly after 24 hours
    earliest_allowed = completed_in_cdmx + 24.hours

    # Build 11:00 am on the same day as earliest_allowed
    candidate = mexico_city.local(
      earliest_allowed.year,
      earliest_allowed.month,
      earliest_allowed.day,
      DELIVERY_HOUR, 0, 0
    )

    # If candidate is at or before earliest_allowed, push to next day's 11am.
    # The "at or before" check ensures we never deliver at the exact 24h mark.
    if candidate <= earliest_allowed
      candidate += 1.day
    end

    candidate
  end

  def perform(job_id)
    job = Job.find_by(id: job_id)
    return unless job

    return if job.review_sent?
    return if job.client&.phone.blank?
    return if job.review_attempts >= MAX_ATTEMPTS

    send_review_request(job)
    track_attempt(job)
    reschedule_if_needed(job)
  end

  private

  # Sends the review request message via WhatsApp to the client
  def send_review_request(job)
    client = job.client
    provider = job.provider

    message = build_review_message(client.name, provider.name)
    WhatsAppService.send_message(to: client.phone, message: message)

    Rails.logger.info(
      "[ReviewRequestJob] Sent review request for Job ##{job.id} " \
      "to #{client.phone} (attempt #{job.review_attempts + 1})"
    )
  end

  # Builds the review request message in warm, colloquial Mexican Spanish.
  # Explicitly instructs the client on how to leave the rating.
  def build_review_message(client_name, provider_name)
    greeting = client_name.present? ? "Hola #{client_name} 👋" : "Hola 👋"

    "#{greeting} Esperamos que el trabajo de #{provider_name} haya quedado a tu gusto. " \
      "¿Nos ayudas con una calificación? Solo responde a este mensaje con un número del 1 al 5 " \
      "(donde 1 es malo y 5 es excelente) ⭐"
  end

  # Increments the attempt counter and records the request timestamp
  def track_attempt(job)
    job.update!(
      review_attempts: job.review_attempts + 1,
      review_requested_at: Time.current
    )
  end

  # Reschedules the job for another attempt if under the max limit.
  # Uses the same 11am CDMX scheduling logic for the next day.
  def reschedule_if_needed(job)
    return if job.review_attempts >= MAX_ATTEMPTS

    next_delivery = self.class.calculate_delivery_time(Time.current)
    ReviewRequestJob.set(wait_until: next_delivery).perform_later(job.id)

    Rails.logger.info(
      "[ReviewRequestJob] Rescheduled Job ##{job.id} for #{next_delivery}"
    )
  end
end
