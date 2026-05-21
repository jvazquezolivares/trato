# frozen_string_literal: true

# Configure ActiveJob to use test adapter in specs
RSpec.configure do |config|
  config.before(:each) do
    ActiveJob::Base.queue_adapter = :test
  end

  config.after(:each) do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end
end
