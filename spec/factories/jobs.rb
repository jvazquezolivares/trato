# frozen_string_literal: true

FactoryBot.define do
  factory :job do
    provider
    client
    description { Faker::Lorem.sentence }
    amount { Faker::Number.decimal(l_digits: 4, r_digits: 2) }
    paid_amount { amount }
    status { "paid" }
    payment_method { "cash" }
    service_date { Date.current }
  end
end
