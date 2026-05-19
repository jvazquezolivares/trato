# frozen_string_literal: true

# Load zones configuration into memory on app boot
# This data is used for region detection, zone selection, and category filtering
# in the dual WhatsApp flows feature.

begin
  zones_file_path = Rails.root.join("config", "zones.json")

  unless File.exist?(zones_file_path)
    raise "zones.json not found at #{zones_file_path}. This file is required for the application to function."
  end

  zones_content = File.read(zones_file_path)
  ZONES_DATA = JSON.parse(zones_content).freeze

  # Validate required structure
  unless ZONES_DATA.is_a?(Hash) && ZONES_DATA.key?("states") && ZONES_DATA.key?("categories")
    raise "zones.json must contain 'states' and 'categories' keys"
  end

  unless ZONES_DATA["states"].is_a?(Array) && ZONES_DATA["categories"].is_a?(Array)
    raise "zones.json 'states' and 'categories' must be arrays"
  end

  Rails.logger.info "✓ Zones data loaded successfully: #{ZONES_DATA['states'].size} states, #{ZONES_DATA['categories'].size} categories"
rescue JSON::ParserError => e
  raise "Invalid JSON in zones.json: #{e.message}"
rescue StandardError => e
  raise "Failed to load zones.json: #{e.message}"
end
