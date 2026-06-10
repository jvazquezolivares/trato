# Procfile for Railway deployment
# This version runs both web and worker in the same container

# For single-container deployment (simpler but less scalable)
web: bundle exec thrust bin/rails server -p ${PORT:-3000} -b 0.0.0.0 & bundle exec sidekiq -C config/sidekiq.yml
