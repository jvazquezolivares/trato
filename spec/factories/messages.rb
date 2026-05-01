# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    conversation
    direction { "inbound" }
    body { Faker::Lorem.sentence }
    processed { false }
  end
end
