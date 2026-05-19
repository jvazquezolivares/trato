# frozen_string_literal: true

# Service to load and query zones, cities, phone prefixes, and categories from config/zones.json
# This service provides deterministic responses for location and category data without AI interpretation
class ZonesService
  class << self
    # Returns array of all state hashes from zones.json
    # @return [Array<Hash>] Array of state objects with name, phone_prefixes, and cities
    def all_states
      zones_data["states"]
    end

    # Detects state from phone number prefix
    # @param phone [String] Phone number to analyze (e.g., "5212291234567")
    # @return [String, nil] State name if prefix matches, nil otherwise
    def detect_state_from_prefix(phone)
      # Extract prefix from phone number (remove country code if present)
      # Phone format: 521 + area_code + number or just area_code + number
      cleaned_phone = phone.to_s.gsub(/\D/, "") # Remove non-digits

      # Try to extract 3-digit prefix (most common in Mexico)
      # If phone starts with 521 (Mexico country code), skip it
      prefix = if cleaned_phone.start_with?("521")
                 cleaned_phone[3..5] # Get 3 digits after 521
               elsif cleaned_phone.start_with?("52")
                 cleaned_phone[2..4] # Get 3 digits after 52
               else
                 cleaned_phone[0..2] # Get first 3 digits
               end

      return nil if prefix.nil? || prefix.length < 3

      # Search for matching state by phone prefix
      all_states.find do |state|
        state["phone_prefixes"].include?(prefix)
      end&.dig("name")
    end

    # Returns array of zones for a given state name
    # @param state_name [String] Name of the state (e.g., "Veracruz")
    # @return [Array<String>] Flattened array of all zones in that state
    def zones_for_state(state_name)
      state = all_states.find { |s| s["name"] == state_name }
      return [] unless state

      state["cities"].flat_map { |city| city["zones"] }
    end

    # Returns flattened array of all zones across all states
    # @return [Array<String>] All zones from all cities in all states
    def all_zones
      all_states.flat_map do |state|
        state["cities"].flat_map { |city| city["zones"] }
      end
    end

    # Returns array of all service categories from zones.json
    # @return [Array<Hash>] Array of category objects with id, name, icon, and slug
    def all_categories
      zones_data["categories"]
    end

    # Returns paginated categories for display in List Messages
    # Page 1: first 5 categories + "Ver más categorías" option
    # Page 2: remaining categories
    # @param page_number [Integer] Page number (1 or 2)
    # @return [Array<Hash>] Array of category objects for the requested page
    def categories_page(page_number)
      categories = all_categories

      case page_number
      when 1
        categories.first(5)
      when 2
        categories.drop(5)
      else
        []
      end
    end

    private

    # Loads and caches zones data from config/zones.json
    # @return [Hash] Parsed JSON data with states and categories
    def zones_data
      @zones_data ||= begin
        file_path = Rails.root.join("config", "zones.json")

        unless File.exist?(file_path)
          raise "zones.json not found at #{file_path}. This file is required for the application to function."
        end

        JSON.parse(File.read(file_path))
      rescue JSON::ParserError => e
        raise "Invalid JSON in zones.json: #{e.message}"
      end
    end
  end
end
