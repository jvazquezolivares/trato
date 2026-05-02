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
    message = build_reminder_message(appointment, provider, client)

    WhatsAppService.send_message(to: client.phone, message: message)

    Rails.logger.info(
      "[AppointmentReminderJob] Sent reminder for Appointment ##{appointment.id} " \
      "to #{client.phone}"
    )
  end

  private

  # Builds the appointment reminder in warm, colloquial Mexican Spanish.
  # Max 2 emojis, 5-6 lines. Includes provider name, service description,
  # scheduled time, and address.
  def build_reminder_message(appointment, provider, client)
    greeting = client.name.present? ? "Hola #{client.name}" : "Hola"
    scheduled_time = appointment.scheduled_at&.strftime("%d/%m/%Y a las %H:%M")
    description = appointment.description.presence || "tu servicio"
    address_line = appointment.address.present? ? "\n📍 #{appointment.address}" : ""

    "#{greeting} 👋\n" \
      "Te recordamos que tienes una cita con #{provider.name} " \
      "para #{description} programada el #{scheduled_time}.#{address_line}\n" \
      "¡Te esperamos!"
  end
end
