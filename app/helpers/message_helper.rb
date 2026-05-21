# frozen_string_literal: true

# Helper module for accessing centralized messages from YAML files.
# Provides a clean interface to retrieve localized messages with interpolation.
#
# Usage:
#   MessageHelper.get(:appointment, :slot_reserved, time: "10:00", date: "mañana")
#   # => "Perfecto, reservé el horario de 10:00 para mañana. Tienes 5 minutos..."
#
#   MessageHelper.button(:confirm)
#   # => "Sí, confirmar"
module MessageHelper
  # Retrieves a message from the messages YAML file.
  #
  # @param category [Symbol] The message category (e.g., :appointment, :provider)
  # @param key [Symbol] The message key within the category
  # @param interpolations [Hash] Variables to interpolate in the message
  # @return [String] The formatted message
  #
  # @example
  #   MessageHelper.get(:appointment, :slot_reserved, time: "10:00", date: "mañana")
  def self.get(category, key, **interpolations)
    I18n.t("messages.#{category}.#{key}", **interpolations)
  end

  # Retrieves a button label from the messages YAML file.
  #
  # @param key [Symbol] The button key (e.g., :confirm, :cancel)
  # @param interpolations [Hash] Variables to interpolate in the label
  # @return [String] The button label
  #
  # @example
  #   MessageHelper.button(:confirm)
  #   # => "Sí, confirmar"
  def self.button(key, **interpolations)
    I18n.t("messages.buttons.#{key}", **interpolations)
  end

  # Retrieves a prompt from the messages YAML file.
  #
  # @param key [Symbol] The prompt key (e.g., :confirm_or_cancel)
  # @return [String] The prompt text
  #
  # @example
  #   MessageHelper.prompt(:confirm_or_cancel)
  #   # => "¿Qué prefieres?"
  def self.prompt(key)
    I18n.t("messages.prompts.#{key}")
  end
end
