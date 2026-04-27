# frozen_string_literal: true

# == Schema Information
#
# Table name: clients
#
#  id         :bigint       not null, primary key
#  name       :string
#  phone      :string       unique
#  rating     :decimal
#  created_at :datetime     not null
#  updated_at :datetime     not null
#
# Indexes: phone (unique)
#
# Client records are GLOBAL — shared across all providers.
# Use find_or_create_by(phone:) and update missing fields on reuse.
class Client < ApplicationRecord
  has_many :provider_clients, dependent: :destroy
  has_many :providers, through: :provider_clients
  has_many :appointments, dependent: :destroy
  has_many :jobs, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :reviews, dependent: :destroy
  has_many :conversations, dependent: :destroy
end
