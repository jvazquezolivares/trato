# frozen_string_literal: true

# == Schema Information
#
# Table name: tasks
#
#  id           :bigint       not null, primary key
#  completed_at :datetime
#  description  :text
#  priority     :string         low | normal | urgent
#  snoozed_until :datetime
#  status       :string         pending | done | snoozed
#  created_at   :datetime     not null
#  updated_at   :datetime     not null
#  provider_id  :bigint       not null, FK → providers
#  work_day_id  :bigint       FK → work_days
#
class Task < ApplicationRecord
  belongs_to :provider
  belongs_to :work_day, optional: true
end
