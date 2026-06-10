# Procfile for Railway deployment
# Railway will execute different processes based on the service configuration

# Web process: Rails server only
web: bundle exec puma -C config/puma.rb

# Worker process: Sidekiq for background jobs
# This should be configured as a separate service in Railway
worker: bundle exec sidekiq -C config/sidekiq.yml
