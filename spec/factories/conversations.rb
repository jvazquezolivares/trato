# frozen_string_literal: true

FactoryBot.define do
  factory :conversation do
    provider
    phone { provider&.phone || "521#{Faker::Number.number(digits: 10)}" }
    role { "provider" }
    stage { "active" }
    context { {} }
    last_message_at { Time.current }
  end
end
