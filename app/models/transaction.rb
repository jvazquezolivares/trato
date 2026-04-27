# frozen_string_literal: true

# == Schema Information
#
# Table name: transactions
#
#  id               :bigint       not null, primary key
#  amount           :decimal
#  assigned_to      :string         job_id reference or "general"
#  description      :text
#  payment_method   :string         cash | transfer
#  recorded_at      :datetime
#  transaction_type :string         income | expense (NOT "type" — avoids STI)
#  created_at       :datetime     not null
#  updated_at       :datetime     not null
#  client_id        :bigint       FK → clients
#  job_id           :bigint       FK → jobs
#  provider_id      :bigint       not null, FK → providers
#
# Indexes: [provider_id, recorded_at], [provider_id, transaction_type]
#
class Transaction < ApplicationRecord
  belongs_to :provider
  belongs_to :job, optional: true
  belongs_to :client, optional: true

  # Disable STI — this model uses `transaction_type` instead of `type`
  self.inheritance_column = nil
end
