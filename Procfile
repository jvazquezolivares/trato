# Procfile for Railway deployment
# Railway will execute the 'web' process by default

# Web process runs both Rails server and Sidekiq using bash
# The trap ensures both processes are cleaned up on shutdown
web: bash -c 'trap "kill 0" EXIT; bundle exec thrust bin/rails server -p ${PORT:-3000} -b 0.0.0.0 & bundle exec sidekiq -C config/sidekiq.yml & wait'
