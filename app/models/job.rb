# frozen_string_literal: true

# == Schema Information
#
# Table name: jobs
#
#  id                  :bigint       not null, primary key
#  amount              :decimal
#  description         :text
#  paid_amount         :decimal      default(0.0)
#  payment_method      :string         cash | transfer | pending
#  review_requested_at :datetime
#  review_sent         :boolean      default(false)
#  service_date        :date
#  status              :string         pending | partial | paid
#  created_at          :datetime     not null
#  updated_at          :datetime     not null
#  appointment_id      :bigint       FK → appointments
#  client_id           :bigint       not null, FK → clients
#  provider_id         :bigint       not null, FK → providers
#
# Indexes: [provider_id, status], [provider_id, service_date]
#
class Job < ApplicationRecord
  belongs_to :provider
  belongs_to :client
  belongs_to :appointment, optional: true

  has_many :transactions, dependent: :destroy
  has_one :review, dependent: :destroy
  has_many :photos, dependent: :nullify
end
