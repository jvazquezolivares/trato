# frozen_string_literal: true

# == Schema Information
#
# Table name: conversations
#
#  id              :bigint       not null, primary key
#  context         :jsonb          LLM working memory (keys in English)
#  last_message_at :datetime
#  phone           :string       unique
#  role            :string         provider | client
#  stage           :string         active | collecting_info | scheduling |
#                                  awaiting_provider | awaiting_client | escalated | closed
#  created_at      :datetime     not null
#  updated_at      :datetime     not null
#  client_id       :bigint       FK → clients
#  provider_id     :bigint       not null, FK → providers
#
# Indexes: phone (unique), [provider_id, stage]
#
# Only created when a Provider is identified. Pre-provider state
# (welcome, onboarding field collection) lives in Redis.
#
class Conversation < ApplicationRecord
  belongs_to :provider
  belongs_to :client, optional: true

  has_many :messages, dependent: :destroy
end
