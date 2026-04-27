# frozen_string_literal: true

# == Schema Information
#
# Table name: reviews
#
#  id          :bigint       not null, primary key
#  comment     :text
#  rating      :integer        1–5
#  verified    :boolean      default(true)
#  created_at  :datetime     not null
#  updated_at  :datetime     not null
#  client_id   :bigint       not null, FK → clients
#  job_id      :bigint       not null, FK → jobs (unique)
#  provider_id :bigint       not null, FK → providers
#
class Review < ApplicationRecord
  belongs_to :provider
  belongs_to :client
  belongs_to :job
end
