# frozen_string_literal: true

# Adds a review_attempts counter to the jobs table so ReviewRequestJob
# can track how many times a review request has been sent (max 3).
class AddReviewAttemptsToJobs < ActiveRecord::Migration[8.1]
  def change
    add_column :jobs, :review_attempts, :integer, default: 0, null: false
  end
end
