# frozen_string_literal: true

# == Schema Information
#
# Table name: provider_clients
#
#  id               :bigint       not null, primary key
#  last_contacted_at :datetime
#  notes            :text
#  created_at       :datetime     not null
#  updated_at       :datetime     not null
#  client_id        :bigint       not null, FK → clients
#  provider_id      :bigint       not null, FK → providers
#
# Indexes: [provider_id, client_id] (unique)
#
class ProviderClient < ApplicationRecord
  belongs_to :provider
  belongs_to :client
end
