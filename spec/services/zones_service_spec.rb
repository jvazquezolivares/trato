# frozen_string_literal: true

require "rails_helper"

RSpec.describe ZonesService do
  describe ".all_states" do
    it "returns an array of state hashes" do
      states = described_class.all_states

      expect(states).to be_an(Array)
      expect(states).not_to be_empty
    end

    it "returns states with required attributes" do
      states = described_class.all_states

      states.each do |state|
        expect(state).to have_key("name")
        expect(state).to have_key("phone_prefixes")
        expect(state).to have_key("cities")
      end
    end

    it "returns all configured states from zones.json" do
      states = described_class.all_states
      state_names = states.map { |s| s["name"] }

      expect(state_names).to include("Veracruz", "Puebla", "Hidalgo", "Oaxaca")
    end

    it "returns states with phone_prefixes as arrays" do
      states = described_class.all_states

      states.each do |state|
        expect(state["phone_prefixes"]).to be_an(Array)
        expect(state["phone_prefixes"]).not_to be_empty
      end
    end

    it "returns states with cities as arrays" do
      states = described_class.all_states

      states.each do |state|
        expect(state["cities"]).to be_an(Array)
        expect(state["cities"]).not_to be_empty
      end
    end

    it "returns cities with required attributes" do
      states = described_class.all_states

      states.each do |state|
        state["cities"].each do |city|
          expect(city).to have_key("name")
          expect(city).to have_key("type")
          expect(city).to have_key("zones")
          expect(city["zones"]).to be_an(Array)
        end
      end
    end
  end

  describe ".detect_state_from_prefix" do
    context "when phone number starts with 521 (Mexico country code + 1)" do
      it "detects Veracruz from prefix 229" do
        phone = "5212291234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end

      it "detects Veracruz from prefix 228" do
        phone = "5212281234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end

      it "detects Puebla from prefix 222" do
        phone = "5212221234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Puebla")
      end

      it "detects Hidalgo from prefix 771" do
        phone = "5217711234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Hidalgo")
      end

      it "detects Oaxaca from prefix 951" do
        phone = "5219511234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Oaxaca")
      end
    end

    context "when phone number starts with 52 (Mexico country code)" do
      it "detects Veracruz from prefix 229" do
        phone = "522291234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end

      it "detects Puebla from prefix 222" do
        phone = "522221234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Puebla")
      end

      it "detects Hidalgo from prefix 771" do
        phone = "527711234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Hidalgo")
      end

      it "detects Oaxaca from prefix 951" do
        phone = "529511234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Oaxaca")
      end
    end

    context "when phone number has no country code" do
      it "detects Veracruz from prefix 229" do
        phone = "2291234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end

      it "detects Puebla from prefix 222" do
        phone = "2221234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Puebla")
      end

      it "detects Hidalgo from prefix 771" do
        phone = "7711234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Hidalgo")
      end

      it "detects Oaxaca from prefix 951" do
        phone = "9511234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Oaxaca")
      end
    end

    context "when testing all 4 states" do
      it "detects all Veracruz prefixes correctly" do
        veracruz_prefixes = ["229", "228", "271", "278", "282", "283", "284", "288"]

        veracruz_prefixes.each do |prefix|
          phone = "521#{prefix}1234567"
          expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz"),
                                                                       "Failed for prefix #{prefix}"
        end
      end

      it "detects all Puebla prefixes correctly" do
        puebla_prefixes = ["222", "223", "224", "226", "227", "231", "233", "236", "237", "243", "244", "249"]

        puebla_prefixes.each do |prefix|
          phone = "521#{prefix}1234567"
          expect(described_class.detect_state_from_prefix(phone)).to eq("Puebla"),
                                                                     "Failed for prefix #{prefix}"
        end
      end

      it "detects all Hidalgo prefixes correctly" do
        hidalgo_prefixes = ["771", "772", "773", "774", "775", "776", "778", "779"]

        hidalgo_prefixes.each do |prefix|
          phone = "521#{prefix}1234567"
          expect(described_class.detect_state_from_prefix(phone)).to eq("Hidalgo"),
                                                                     "Failed for prefix #{prefix}"
        end
      end

      it "detects all Oaxaca prefixes correctly" do
        oaxaca_prefixes = ["951", "953", "954", "958", "971", "972"]

        oaxaca_prefixes.each do |prefix|
          phone = "521#{prefix}1234567"
          expect(described_class.detect_state_from_prefix(phone)).to eq("Oaxaca"),
                                                                     "Failed for prefix #{prefix}"
        end
      end
    end

    context "when phone number has non-digit characters" do
      it "handles phone with spaces" do
        phone = "521 229 123 4567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end

      it "handles phone with dashes" do
        phone = "521-229-123-4567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end

      it "handles phone with parentheses" do
        phone = "+52 (229) 123-4567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end

      it "handles phone with plus sign" do
        phone = "+5212291234567"
        expect(described_class.detect_state_from_prefix(phone)).to eq("Veracruz")
      end
    end

    context "when phone prefix does not match any state" do
      it "returns nil for unknown prefix" do
        phone = "5211111234567"
        expect(described_class.detect_state_from_prefix(phone)).to be_nil
      end

      it "returns nil for invalid phone number" do
        phone = "123"
        expect(described_class.detect_state_from_prefix(phone)).to be_nil
      end

      it "returns nil for empty string" do
        phone = ""
        expect(described_class.detect_state_from_prefix(phone)).to be_nil
      end

      it "returns nil for nil input" do
        phone = nil
        expect(described_class.detect_state_from_prefix(phone)).to be_nil
      end
    end
  end

  describe ".all_zones" do
    it "returns an array of all zones across all states" do
      zones = described_class.all_zones

      expect(zones).to be_an(Array)
      expect(zones).not_to be_empty
    end

    it "returns zones as strings" do
      zones = described_class.all_zones

      expect(zones).to all(be_a(String))
    end

    it "includes zones from all states" do
      zones = described_class.all_zones

      # Should include zones from Veracruz, Puebla, Hidalgo, and Oaxaca
      # Verify by checking that we have a significant number of zones
      expect(zones.length).to be > 10
    end

    it "flattens zones from all cities in all states" do
      zones = described_class.all_zones

      # Zones should be a flat array, not nested
      expect(zones).to all(be_a(String))
      expect(zones.first).not_to be_an(Array)
    end

    it "includes zones from multiple states" do
      all_zones = described_class.all_zones
      veracruz_zones = described_class.zones_for_state("Veracruz")
      puebla_zones = described_class.zones_for_state("Puebla")

      # all_zones should include zones from both Veracruz and Puebla
      expect(all_zones).to include(*veracruz_zones.first(2))
      expect(all_zones).to include(*puebla_zones.first(2))
    end

    it "returns more zones than any single state" do
      all_zones = described_class.all_zones
      veracruz_zones = described_class.zones_for_state("Veracruz")

      expect(all_zones.length).to be > veracruz_zones.length
    end
  end

  describe ".zones_for_state" do
    context "when state exists" do
      it "returns array of zones for Veracruz" do
        zones = described_class.zones_for_state("Veracruz")

        expect(zones).to be_an(Array)
        expect(zones).not_to be_empty
      end

      it "returns array of zones for Puebla" do
        zones = described_class.zones_for_state("Puebla")

        expect(zones).to be_an(Array)
        expect(zones).not_to be_empty
      end

      it "returns array of zones for Hidalgo" do
        zones = described_class.zones_for_state("Hidalgo")

        expect(zones).to be_an(Array)
        expect(zones).not_to be_empty
      end

      it "returns array of zones for Oaxaca" do
        zones = described_class.zones_for_state("Oaxaca")

        expect(zones).to be_an(Array)
        expect(zones).not_to be_empty
      end

      it "returns flattened zones from all cities in the state" do
        zones = described_class.zones_for_state("Veracruz")

        # Zones should be strings, not nested arrays
        expect(zones).to all(be_a(String))
      end

      it "includes zones from multiple cities in the same state" do
        zones = described_class.zones_for_state("Veracruz")

        # Veracruz state should have zones from multiple cities
        # (e.g., Veracruz city, Xalapa, Coatzacoalcos, etc.)
        expect(zones.length).to be > 5
      end
    end

    context "when state does not exist" do
      it "returns empty array for unknown state" do
        zones = described_class.zones_for_state("Unknown State")

        expect(zones).to eq([])
      end

      it "returns empty array for nil state" do
        zones = described_class.zones_for_state(nil)

        expect(zones).to eq([])
      end

      it "returns empty array for empty string" do
        zones = described_class.zones_for_state("")

        expect(zones).to eq([])
      end
    end

    context "when state name is case-sensitive" do
      it "returns empty array for lowercase state name" do
        zones = described_class.zones_for_state("veracruz")

        expect(zones).to eq([])
      end

      it "returns zones for exact case match" do
        zones = described_class.zones_for_state("Veracruz")

        expect(zones).not_to be_empty
      end
    end
  end

  describe ".all_categories" do
    it "returns an array of category hashes" do
      categories = described_class.all_categories

      expect(categories).to be_an(Array)
      expect(categories).not_to be_empty
    end

    it "returns categories with required attributes" do
      categories = described_class.all_categories

      categories.each do |category|
        expect(category).to have_key("id")
        expect(category).to have_key("name")
        expect(category).to have_key("icon")
        expect(category).to have_key("slug")
      end
    end

    it "returns categories with correct data types" do
      categories = described_class.all_categories

      categories.each do |category|
        expect(category["id"]).to be_a(String)
        expect(category["name"]).to be_a(String)
        expect(category["icon"]).to be_a(String)
        expect(category["slug"]).to be_a(String)
      end
    end

    it "includes expected service categories" do
      categories = described_class.all_categories
      category_names = categories.map { |c| c["name"] }

      expect(category_names).to include("Plomería")
      expect(category_names).to include("Electricidad")
    end

    it "returns categories with icons" do
      categories = described_class.all_categories

      categories.each do |category|
        expect(category["icon"]).not_to be_empty
      end
    end

    it "returns categories with unique ids" do
      categories = described_class.all_categories
      category_ids = categories.map { |c| c["id"] }

      expect(category_ids.uniq.length).to eq(category_ids.length)
    end

    it "returns categories with unique slugs" do
      categories = described_class.all_categories
      category_slugs = categories.map { |c| c["slug"] }

      expect(category_slugs.uniq.length).to eq(category_slugs.length)
    end
  end

  describe ".categories_page" do
    context "when requesting page 1" do
      it "returns first 5 categories" do
        page_1_categories = described_class.categories_page(1)

        expect(page_1_categories).to be_an(Array)
        expect(page_1_categories.length).to eq(5)
      end

      it "returns categories with all required attributes" do
        page_1_categories = described_class.categories_page(1)

        page_1_categories.each do |category|
          expect(category).to have_key("id")
          expect(category).to have_key("name")
          expect(category).to have_key("icon")
          expect(category).to have_key("slug")
        end
      end

      it "returns the first 5 categories from all_categories" do
        all_categories = described_class.all_categories
        page_1_categories = described_class.categories_page(1)

        expect(page_1_categories).to eq(all_categories.first(5))
      end
    end

    context "when requesting page 2" do
      it "returns remaining categories after first 5" do
        all_categories = described_class.all_categories
        page_2_categories = described_class.categories_page(2)

        expect(page_2_categories).to be_an(Array)
        expect(page_2_categories.length).to eq(all_categories.length - 5)
      end

      it "returns categories with all required attributes" do
        page_2_categories = described_class.categories_page(2)

        page_2_categories.each do |category|
          expect(category).to have_key("id")
          expect(category).to have_key("name")
          expect(category).to have_key("icon")
          expect(category).to have_key("slug")
        end
      end

      it "returns categories starting from 6th category" do
        all_categories = described_class.all_categories
        page_2_categories = described_class.categories_page(2)

        expect(page_2_categories).to eq(all_categories.drop(5))
      end

      it "does not overlap with page 1 categories" do
        page_1_categories = described_class.categories_page(1)
        page_2_categories = described_class.categories_page(2)

        page_1_ids = page_1_categories.map { |c| c["id"] }
        page_2_ids = page_2_categories.map { |c| c["id"] }

        expect(page_1_ids & page_2_ids).to be_empty
      end
    end

    context "when requesting invalid page number" do
      it "returns empty array for page 0" do
        categories = described_class.categories_page(0)

        expect(categories).to eq([])
      end

      it "returns empty array for page 3" do
        categories = described_class.categories_page(3)

        expect(categories).to eq([])
      end

      it "returns empty array for negative page number" do
        categories = described_class.categories_page(-1)

        expect(categories).to eq([])
      end
    end

    context "when combining both pages" do
      it "returns all categories when combining page 1 and page 2" do
        all_categories = described_class.all_categories
        page_1_categories = described_class.categories_page(1)
        page_2_categories = described_class.categories_page(2)

        combined_categories = page_1_categories + page_2_categories

        expect(combined_categories.length).to eq(all_categories.length)
        expect(combined_categories.map { |c| c["id"] }).to eq(all_categories.map { |c| c["id"] })
      end
    end
  end
end
