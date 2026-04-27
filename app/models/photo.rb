# frozen_string_literal: true

# == Schema Information
#
# Table name: photos
#
#  id            :bigint       not null, primary key
#  caption       :text
#  category_tags :jsonb          array of category slugs
#  profile_photo :boolean      default(false)
#  url           :string         S3 URL via Active Storage
#  created_at    :datetime     not null
#  updated_at    :datetime     not null
#  job_id        :bigint       FK → jobs
#  provider_id   :bigint       not null, FK → providers
#
class Photo < ApplicationRecord
  belongs_to :provider
  belongs_to :job, optional: true

  has_many :social_posts, dependent: :destroy
end
