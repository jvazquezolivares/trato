# Procfile for Railway deployment
# Railway will execute the 'web' process by default

# Start Sidekiq in daemon mode first, then start Rails server
web: bundle exec sidekiq -C config/sidekiq.yml -d && bundle exec puma -C config/puma.rb
