# frozen_string_literal: true

FactoryBot.define do
  factory :transaction do
    provider
    amount { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    transaction_type { "income" }
    description { Faker::Lorem.sentence }
    payment_method { "cash" }
    recorded_at { Time.current }
    assigned_to { "general" }
  end
end
