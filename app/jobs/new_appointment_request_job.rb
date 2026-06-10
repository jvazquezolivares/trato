# frozen_string_literal: true

# Sends a WhatsApp notification to a Provider when a Client books a new Appointment.
#
# Enqueued per-appointment when an Appointment is created via the client-side assistant.
# Uses the "new_appointment_request" Message Template approved by Meta.
#
# Guard clauses:
#   - Skips silently if Appointment not found
#   - Skips silently if Appointment is cancelled
#   - Skips silently if Provider has no phone on record
class NewAppointmentRequestJob < ApplicationJob
  queue_as :default

  def perform(appointment_id)
    appointment = Appointment.find_by(id: appointment_id)
    return unless appointment
    return if appointment.status == "cancelled"

    provider = appointment.provider
    return if provider.phone.blank?

    client = appointment.client

    # Format appointment details for template parameters
    client_name = client.name.presence || "Un cliente"
    problem_description = appointment.description.presence || "servicio solicitado"
    appointment_date = appointment.scheduled_at&.strftime("%d/%m/%Y") || "próximamente"
    appointment_time = appointment.scheduled_at&.strftime("%H:%M") || "por confirmar"

    # Use template message (new_appointment_request) to notify provider
    WhatsAppService.send_template_message(
      to: provider.phone,
      template_name: "new_appointment_request",
      parameters: [client_name, problem_description, appointment_date, appointment_time],
      phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
    )

    Rails.logger.info(
      "[NewAppointmentRequestJob] Sent new appointment request template for Appointment ##{appointment.id} " \
      "to provider #{provider.phone}"
    )
  end
end
