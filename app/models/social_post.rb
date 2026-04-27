# frozen_string_literal: true

# == Schema Information
#
# Table name: social_posts
#
#  id                :bigint       not null, primary key
#  caption_generated :text
#  error_message     :text
#  platform          :string         facebook | instagram | both
#  published_at      :datetime
#  status            :string         pending | published | failed
#  created_at        :datetime     not null
#  updated_at        :datetime     not null
#  photo_id          :bigint       not null, FK → photos
#  provider_id       :bigint       not null, FK → providers
#
class SocialPost < ApplicationRecord
  belongs_to :provider
  belongs_to :photo
end
