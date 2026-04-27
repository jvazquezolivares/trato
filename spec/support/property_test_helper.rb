# frozen_string_literal: true

# Shared helpers for property-based tests.
#
# Memory suite: uses build_stubbed from FactoryBot, 100 iterations, no DB writes.
# DB suite: uses create with DatabaseCleaner, 25 iterations.
module PropertyTestHelper
  MEMORY_ITERATIONS = 100
  DB_ITERATIONS = 25

  # Generates a random Mexican phone number that won't collide with real providers.
  def random_phone
    "521#{rand(1_000_000_000..9_999_999_999)}"
  end

  # Generates a random body that is NOT a valid 8-char hex short_uuid.
  def random_non_uuid_body
    candidates = [
      Faker::Lorem.sentence,
      Faker::Name.name,
      rand(100..999).to_s,
      "hola",
      "necesito ayuda",
      "buenos dias",
      ""
    ]
    candidates.sample
  end
end

RSpec.configure do |config|
  config.include PropertyTestHelper, type: :property
end
