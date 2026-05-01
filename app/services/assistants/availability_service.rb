# frozen_string_literal: true

module Assistants
  # Queries a provider's WorkDay records and builds a human-readable
  # availability summary for the system prompt.
  #
  # Usage:
  #   Assistants::AvailabilityService.call(provider: provider)
  #   # => "Disponible hoy de 08:00 a 18:00"
  class AvailabilityService
    def self.call(provider:, date: Date.current)
      new(provider: provider, date: date).summary
    end

    def initialize(provider:, date:)
      @provider = provider
      @date = date
    end

    def summary
      work_day = @provider.work_days.find_by(date: @date)

      return "No ha reportado disponibilidad hoy" unless work_day

      format_work_day(work_day)
    end

    private

    def format_work_day(work_day)
      starts = work_day.starts_at&.strftime("%H:%M")
      ends = work_day.ends_at&.strftime("%H:%M")

      case work_day.status
      when "active"
        "Disponible hoy de #{starts} a #{ends}"
      when "finished"
        "Ya terminó su jornada hoy"
      when "planning"
        "Planificando su día (#{starts} a #{ends})"
      else
        "Estado: #{work_day.status}"
      end
    end
  end
end
