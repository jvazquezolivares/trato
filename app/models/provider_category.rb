# frozen_string_literal: true

# == Schema Information
#
# Table name: provider_categories
#
#  id          :bigint       not null, primary key
#  name        :string
#  primary     :boolean      default(false)
#  slug        :string
#  created_at  :datetime     not null
#  updated_at  :datetime     not null
#  provider_id :bigint       not null, FK → providers
#
# Indexes: [provider_id, slug] (unique), [provider_id, primary]
#
class ProviderCategory < ApplicationRecord
  belongs_to :provider
end
