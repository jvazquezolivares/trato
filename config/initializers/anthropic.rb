# frozen_string_literal: true

# Configure Anthropic API client
Anthropic.setup do |config|
  config.api_key = ENV.fetch("ANTHROPIC_API_KEY")
end
