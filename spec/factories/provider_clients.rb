# frozen_string_literal: true

FactoryBot.define do
  factory :provider_client do
    provider
    client
    last_contacted_at { Time.current }
  end
end
