# frozen_string_literal: true

FactoryBot.define do
  factory :work_day do
    provider
    date { Date.current }
    starts_at { "08:00" }
    ends_at { "18:00" }
    status { "active" }
    notes { nil }
  end
end
