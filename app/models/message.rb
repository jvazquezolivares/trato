# frozen_string_literal: true

# == Schema Information
#
# Table name: messages
#
#  id              :bigint       not null, primary key
#  body            :text
#  direction       :string         inbound | outbound
#  intent          :string
#  media_url       :string
#  processed       :boolean      default(false)
#  created_at      :datetime     not null
#  updated_at      :datetime     not null
#  conversation_id :bigint       not null, FK → conversations
#
# Indexes: [conversation_id, created_at], processed (partial WHERE false)
#
class Message < ApplicationRecord
  belongs_to :conversation
end
