# frozen_string_literal: true

# Pure logic service that classifies messages as trivial or critical
# based on body content and intent.
#
# Trivial messages (should NOT be saved):
#   "ok", "gracias", "perfecto", "listo", "entendido", "si", "no",
#   standalone emojis
#
# Critical intents (should ALWAYS be saved):
#   job_registered, payment_recorded, appointment_confirmed,
#   appointment_cancelled, complaint_received, client_first_contact,
#   provider_unavailable, expense_registered
#
# Usage:
#   MessagePersistenceFilter.should_save?(body: "ok", intent: nil)
#   # => false
#
#   MessagePersistenceFilter.should_save?(body: "anything", intent: "job_registered")
#   # => true
class MessagePersistenceFilter
  TRIVIAL_BODIES = %w[
    ok gracias perfecto listo entendido si no
  ].freeze

  CRITICAL_INTENTS = %w[
    job_registered payment_recorded appointment_confirmed
    appointment_cancelled complaint_received client_first_contact
    provider_unavailable expense_registered
  ].freeze

  # Unicode emoji detection: matches standalone emoji-only messages.
  # Covers emoji with presentation selectors and ZWJ sequences.
  # Uses \p{Emoji_Presentation} for default-emoji characters (e.g. 😊, 👍)
  # and \p{Emoji}\uFE0F for text-default emojis rendered as emoji (e.g. ❤️).
  # Excludes bare ASCII digits/symbols which are technically \p{Emoji}.
  EMOJI_ONLY_PATTERN = /\A(?:[\p{Emoji_Presentation}]|\p{Emoji}\uFE0F)[\p{Emoji_Presentation}\p{Emoji}\u{FE0F}\u{200D}\u{20E3}\s]*\z/

  # Determines whether a message should be persisted.
  #
  # @param body [String, nil] the message body text
  # @param intent [String, nil] the classified intent from Claude
  # @return [Boolean] true if the message should be saved
  def self.should_save?(body:, intent:)
    return true if critical_intent?(intent)
    return false if trivial_body?(body)

    # Default: defer to Claude's should_save_message flag (not handled here)
    # This filter only handles the deterministic trivial/critical cases.
    nil
  end

  # Checks if the intent is in the critical set.
  #
  # @param intent [String, nil] the intent to check
  # @return [Boolean]
  def self.critical_intent?(intent)
    return false if intent.blank?

    CRITICAL_INTENTS.include?(intent.to_s.strip.downcase)
  end

  # Checks if the body is trivial (should not be saved).
  #
  # @param body [String, nil] the body to check
  # @return [Boolean]
  def self.trivial_body?(body)
    return true if body.blank?

    normalized = body.to_s.strip.downcase

    return true if TRIVIAL_BODIES.include?(normalized)
    return true if standalone_emoji?(normalized)

    false
  end

  # Checks if the string consists only of emoji characters.
  #
  # @param text [String] the text to check
  # @return [Boolean]
  def self.standalone_emoji?(text)
    return false if text.empty?

    EMOJI_ONLY_PATTERN.match?(text)
  end

  private_class_method :standalone_emoji?
end
