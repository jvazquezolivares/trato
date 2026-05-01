# frozen_string_literal: true

# Sends a review request to a Client after a completed Job.
# Scheduling: minimum 24-hour delay after job completion, delivered at
# 11:00 am Mexico City time (UTC-6) on the first eligible day.
#
# Max 3 delivery attempts per Job. Skips without error if client has no phone.
# Full implementation in task 16.1.
class ReviewRequestJob < ApplicationJob
  queue_as :default

  def perform(job_id)
    job = Job.find_by(id: job_id)
    return unless job
    return if job.review_sent?
    return if job.client&.phone.blank?

    Rails.logger.info("[ReviewRequestJob] Stub — would send review request for Job ##{job_id}")
  end
end
