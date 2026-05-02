# frozen_string_literal: true

module Assistants
  # Manages WorkDay creation and updates for a Provider.
  # Called by ProviderAssistant when Claude detects an "update_work_day" action.
  #
  # Uses find_or_initialize_by on [provider_id, date] to respect the unique
  # index and ensure idempotent upserts for the same day.
  #
  # Usage:
  #   Assistants::WorkDayService.call(
  #     provider: provider,
  #     action_data: { "starts_at" => "08:00", "ends_at" => "18:00", "status" => "active", "notes" => "..." }
  #   )
  class WorkDayService
    VALID_STATUSES = %w[planning active finished].freeze
    DEFAULT_STATUS = "active"

    def self.call(provider:, action_data:)
      new(provider: provider, action_data: action_data).execute
    end

    def initialize(provider:, action_data:)
      @provider = provider
      @action_data = action_data || {}
    end

    def execute
      work_day = find_or_initialize_today
      assign_attributes(work_day)
      work_day.save!
      work_day
    end

    private

    def find_or_initialize_today
      @provider.work_days.find_or_initialize_by(date: Date.current)
    end

    def assign_attributes(work_day)
      work_day.starts_at = parse_time(@action_data["starts_at"]) if @action_data["starts_at"].present?
      work_day.ends_at = parse_time(@action_data["ends_at"]) if @action_data["ends_at"].present?
      work_day.status = sanitize_status(@action_data["status"])
      work_day.notes = @action_data["notes"] if @action_data.key?("notes")
    end

    def sanitize_status(status)
      return DEFAULT_STATUS if status.blank?

      VALID_STATUSES.include?(status) ? status : DEFAULT_STATUS
    end

    # Parses time strings like "08:00", "8:00", "18:30".
    # Rails casts strings to :time columns automatically, so we just
    # validate the format and pass through.
    def parse_time(value)
      return nil if value.blank?

      # Normalize "8:00" → "08:00" for consistent storage
      if value.match?(/\A\d{1,2}:\d{2}\z/)
        hours, minutes = value.split(":").map(&:to_i)
        format("%<hours>02d:%<minutes>02d", hours: hours, minutes: minutes)
      else
        value
      end
    end
  end
end
