# frozen_string_literal: true

FactoryBot.define do
  factory :social_post do
    provider
    photo
    caption_generated { Faker::Lorem.sentence }
    platform { "facebook" }
    status { "pending" }

    trait :published do
      status { "published" }
      published_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_message { "Error al publicar" }
    end

    trait :both_platforms do
      platform { "both" }
    end
  end
end
