# frozen_string_literal: true

FactoryBot.define do
  factory :photo do
    provider
    url { "https://trato-photos.s3.amazonaws.com/photos/#{SecureRandom.hex(8)}.jpg" }
    caption { Faker::Lorem.sentence }
    profile_photo { false }
    category_tags { [] }

    trait :profile do
      profile_photo { true }
    end

    trait :work do
      profile_photo { false }
      category_tags { [Faker::Lorem.word, Faker::Lorem.word] }
    end
  end
end
