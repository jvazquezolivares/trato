# frozen_string_literal: true

FactoryBot.define do
  factory :review do
    provider
    client
    job
    rating { rand(1..5) }
    comment { Faker::Lorem.sentence }
    verified { true }
  end
end
