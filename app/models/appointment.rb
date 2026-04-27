# frozen_string_literal: true

# == Schema Information
#
# Table name: appointments
#
#  id                 :bigint       not null, primary key
#  address            :string
#  description        :text
#  estimated_duration :integer      default(60)
#  how_client_arrived :string         whatsapp_direct | referral | profile_link
#  notes              :text
#  scheduled_at       :datetime
#  status             :string         pending | confirmed | completed | cancelled
#  created_at         :datetime     not null
#  updated_at         :datetime     not null
#  client_id          :bigint       not null, FK → clients
#  provider_id        :bigint       not null, FK → providers
#  work_day_id        :bigint       FK → work_days
#
# Indexes: [provider_id, scheduled_at], client_id, status
#
class Appointment < ApplicationRecord
  belongs_to :provider
  belongs_to :client
  belongs_to :work_day, optional: true

  has_many :jobs, dependent: :nullify
end
