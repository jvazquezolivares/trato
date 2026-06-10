# frozen_string_literal: true

# Background job for processing messages sent to the provider WhatsApp number.
# Routes messages through ProviderConversationHandler which determines the appropriate
# conversation flow based on sender identity (known provider or new user onboarding).
class ProviderMessageJob < ApplicationJob
  queue_as :default

  # Process an incoming WhatsApp message sent to the provider number
  #
  # @param from [String] The sender's phone number (E.164 format)
  # @param body [String] The message text content
  # @param media_url [String, nil] Optional URL to media attachment (image, audio, etc.)
  def perform(from, body, media_url = nil)
    STDOUT.puts "[DEBUG ProviderMessageJob] ===== JOB INICIO ====="
    STDOUT.flush
    STDOUT.puts "[DEBUG ProviderMessageJob] from: #{from}, body: #{body}, media_url: #{media_url}"
    STDOUT.flush

    ProviderConversationHandler.call(
      from: from,
      body: body,
      media_url: media_url
    )

    STDOUT.puts "[DEBUG ProviderMessageJob] ===== JOB COMPLETADO ====="
    STDOUT.flush
  rescue StandardError => e
    STDOUT.puts "[DEBUG ProviderMessageJob] ERROR: #{e.class} - #{e.message}"
    STDOUT.flush
    STDOUT.puts "[DEBUG ProviderMessageJob] Backtrace: #{e.backtrace.first(5).join("\n")}"
    STDOUT.flush
    raise
  end
end
