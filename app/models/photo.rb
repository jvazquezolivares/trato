# frozen_string_literal: true

# == Schema Information
#
# Table name: photos
#
#  id            :bigint       not null, primary key
#  caption       :text
#  category_tags :jsonb          array of category slugs
#  position      :integer      default(0)
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
  has_one_attached :file

  scope :ordered, -> { order(position: :asc, created_at: :desc) }

  # Returns the display URL — Active Storage URL if file attached, otherwise the stored url column
  def display_url
    if file.attached?
      Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true)
    else
      url
    end
  end
end
