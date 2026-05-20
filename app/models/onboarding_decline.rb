# frozen_string_literal: true

# Tracks reasons why potential providers decline registration during onboarding.
# Used for analytics to understand barriers to adoption.
#
# Attributes:
#   phone (string, required): Phone number of the person who declined
#   reason (string, required): Selected decline reason (e.g., "busy", "dont_understand")
#   context (jsonb): Additional context about the decline (e.g., stage, timestamp)
class OnboardingDecline < ApplicationRecord
  validates :phone, presence: true
  validates :reason, presence: true

  # Scope to find declines by phone number
  scope :by_phone, ->(phone) { where(phone: phone) }

  # Scope to find recent declines
  scope :recent, -> { order(created_at: :desc) }
end
