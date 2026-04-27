# frozen_string_literal: true

FactoryBot.define do
  factory :provider do
    name { Faker::Name.name }
    phone { "521#{Faker::Number.number(digits: 10)}" }
    short_uuid { SecureRandom.hex(4) }
    city { Faker::Address.city }
    service_area { Faker::Address.community }
    base_price { Faker::Number.decimal(l_digits: 3, r_digits: 2) }
    bio { Faker::Lorem.paragraph }
    slug { "#{Faker::Lorem.word}-en-#{city&.parameterize}/#{name&.parameterize}-#{short_uuid}" }
    active { true }
  end
end
