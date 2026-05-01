# frozen_string_literal: true

FactoryBot.define do
  factory :provider_category do
    provider
    name { Faker::Job.field }
    slug { name&.parameterize }
    primary { false }
  end
end
