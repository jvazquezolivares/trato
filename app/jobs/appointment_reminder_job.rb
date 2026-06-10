# frozen_string_literal: true

# Sends a WhatsApp reminder to the Client 1 hour before a scheduled Appointment.
#
# Enqueued per-appointment when an Appointment is created via
# Assistants::AppointmentService#schedule_reminder.
#
# Guard clauses:
#   - Skips silently if Appointment not found
#   - Skips silently if Appointment is cancelled
#   - Skips silently if Client has no phone on record
class AppointmentReminderJob < ApplicationJob
  queue_as :default

  def perform(appointment_id)
    appointment = Appointment.find_by(id: appointment_id)
    return unless appointment
    return if appointment.status == "cancelled"

    client = appointment.client
    return if client.phone.blank?

    provider = appointment.provider

    # Format appointment details for template parameters
    recipient_name = client.name.presence || "Cliente"
    other_party_name = provider.name
    appointment_time = appointment.scheduled_at&.strftime("%d/%m/%Y a las %H:%M") || "próximamente"
    location = appointment.address.presence || "ubicación por confirmar"

    # Use template message (appointment_reminder) for client
    WhatsAppService.send_template_message(
      to: client.phone,
      template_name: "appointment_reminder",
      parameters: [recipient_name, other_party_name, appointment_time, location],
      phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
    )

    Rails.logger.info(
      "[AppointmentReminderJob] Sent appointment reminder template for Appointment ##{appointment.id} " \
      "to #{client.phone}"
    )

    # Also send reminder to provider using provider phone number ID
    provider_recipient_name = provider.name
    other_party_for_provider = client.name.presence || "Cliente"

    WhatsAppService.send_template_message(
      to: provider.phone,
      template_name: "appointment_reminder",
      parameters: [provider_recipient_name, other_party_for_provider, appointment_time, location],
      phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
    )

    Rails.logger.info(
      "[AppointmentReminderJob] Sent appointment reminder template for Appointment ##{appointment.id} " \
      "to provider #{provider.phone}"
    )
  end
end
