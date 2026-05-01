# frozen_string_literal: true

FactoryBot.define do
  factory :client do
    name { Faker::Name.name }
    phone { "521#{Faker::Number.number(digits: 10)}" }
  end
end
