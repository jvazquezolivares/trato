# frozen_string_literal: true

module Assistants
  # Creates and manages Task records for a Provider.
  # Called by ProviderAssistant when Claude detects a "create_task" action.
  #
  # Task intent is detected from keywords like: "tengo que", "me falta",
  # "necesito", "acuérdate que", "recuérdame", "no se me olvide".
  #
  # If the task has no associated date (snoozed_until is nil), Claude should
  # ask the provider when they want to be reminded — that follow-up is
  # handled conversationally, not by this service.
  #
  # Usage:
  #   Assistants::TaskService.call(
  #     provider: provider,
  #     action_data: { "description" => "Llamar al señor Pérez", "priority" => "normal", "snoozed_until" => nil }
  #   )
  class TaskService
    VALID_PRIORITIES = %w[low normal urgent].freeze
    DEFAULT_PRIORITY = "normal"

    def self.call(provider:, action_data:)
      new(provider: provider, action_data: action_data).execute
    end

    def initialize(provider:, action_data:)
      @provider = provider
      @action_data = action_data || {}
    end

    def execute
      task = create_task
      Rails.logger.info("[TaskService] Created task ##{task.id} for #{@provider.name}: #{task.description}")
      task
    end

    private

    def create_task
      @provider.tasks.create!(
        description: @action_data["description"],
        status: "pending",
        priority: sanitize_priority(@action_data["priority"]),
        snoozed_until: parse_datetime(@action_data["snoozed_until"])
      )
    end

    def sanitize_priority(priority)
      return DEFAULT_PRIORITY if priority.blank?

      VALID_PRIORITIES.include?(priority) ? priority : DEFAULT_PRIORITY
    end

    # Parses ISO 8601 datetime strings for the snoozed_until field.
    # Returns nil if the value is blank or unparseable.
    def parse_datetime(value)
      return nil if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
