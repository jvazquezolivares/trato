# frozen_string_literal: true

# == Schema Information
#
# Table name: work_days
#
#  id          :bigint       not null, primary key
#  date        :date
#  ends_at     :time
#  notes       :text
#  starts_at   :time
#  status      :string         planning | active | finished
#  created_at  :datetime     not null
#  updated_at  :datetime     not null
#  provider_id :bigint       not null, FK → providers
#
# Indexes: [provider_id, date] (unique)
#
class WorkDay < ApplicationRecord
  belongs_to :provider
  has_many :tasks, dependent: :nullify
  has_many :appointments, dependent: :nullify
end
