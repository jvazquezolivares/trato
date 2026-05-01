# frozen_string_literal: true

module Assistants
  # Creates appointments, notifies providers, and schedules reminders.
  #
  # Usage:
  #   Assistants::AppointmentService.call(
  #     provider: provider, client: client, from: "521...",
  #     action_data: { "date" => "2026-05-02", "time" => "10:00", ... },
  #     conversation: conversation
  #   )
  class AppointmentService
    def self.call(provider:, client:, from:, action_data:, conversation:)
      new(
        provider: provider, client: client, from: from,
        action_data: action_data, conversation: conversation
      ).create
    end

    def initialize(provider:, client:, from:, action_data:, conversation:)
      @provider = provider
      @client = client
      @from = from
      @data = action_data || {}
      @conversation = conversation
    end

    def create
      return unless @client

      appointment = build_appointment
      notify_provider(appointment)
      schedule_reminder(appointment)

      appointment
    end

    private

    def build_appointment
      Appointment.create!(
        provider: @provider,
        client: @client,
        work_day: find_work_day,
        description: @data["description"] || @conversation.context&.dig("service_requested"),
        address: @data["address"] || @conversation.context&.dig("address"),
        scheduled_at: parse_scheduled_at,
        estimated_duration: @data["duration"]&.to_i || 60,
        status: "pending",
        how_client_arrived: "whatsapp_direct",
        notes: @data["notes"]
      )
    end

    def find_work_day
      return nil if @data["date"].blank?

      date = Date.parse(@data["date"])
      @provider.work_days.find_by(date: date)
    rescue Date::Error
      nil
    end

    def parse_scheduled_at
      date = @data["date"].present? ? Date.parse(@data["date"]) : Date.current
      time = @data["time"].present? ? Time.zone.parse("#{date} #{@data['time']}") : Time.zone.parse("#{date} 10:00")

      time || Time.zone.parse("#{date} 10:00")
    rescue Date::Error, ArgumentError
      Time.zone.parse("#{Date.current} 10:00")
    end

    def notify_provider(appointment)
      summary = build_appointment_summary(appointment)
      WhatsAppService.send_message(to: @provider.phone, message: summary)
    end

    def build_appointment_summary(appointment)
      "📋 *Nueva cita agendada*\n\n" \
      "👤 Cliente: #{@client&.name || 'No proporcionado'}\n" \
      "📱 Teléfono: #{@from}\n" \
      "🔧 Servicio: #{appointment.description}\n" \
      "📍 Dirección: #{appointment.address || 'Por confirmar'}\n" \
      "📅 Fecha: #{appointment.scheduled_at&.strftime('%d/%m/%Y %H:%M')}\n" \
      "⏱ Duración estimada: #{appointment.estimated_duration} min\n\n" \
      "¿Confirmas esta cita? Responde *sí* o propón otro horario."
    end

    def schedule_reminder(appointment)
      return unless defined?(AppointmentReminderJob)

      AppointmentReminderJob.set(
        wait_until: appointment.scheduled_at - 1.hour
      ).perform_later(appointment.id)
    rescue StandardError => e
      Rails.logger.warn("[Assistants::AppointmentService] Could not schedule reminder: #{e.message}")
    end
  end
end
