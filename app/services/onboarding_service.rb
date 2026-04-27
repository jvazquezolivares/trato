# frozen_string_literal: true

# Guides unknown numbers through provider registration.
# Collects all fields one at a time, generates bio with Claude Sonnet,
# and creates the Provider record.
# Stub — full implementation in task 7.
class OnboardingService
  def self.call(from:, body:)
    Rails.logger.info("[OnboardingService] Stub called from #{from}")
    nil
  end
end
