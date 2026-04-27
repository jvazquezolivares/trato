# frozen_string_literal: true

# Handles all provider-facing conversations (Miguel's assistant).
# Manages WorkDay, Task, Job, Transaction, Appointment, and social media flows.
# Stub — full implementation in task 11.
class ProviderAssistant
  def self.call(provider:, body:, media_url: nil)
    Rails.logger.info("[ProviderAssistant] Stub called for provider #{provider&.phone}")
    nil
  end
end
