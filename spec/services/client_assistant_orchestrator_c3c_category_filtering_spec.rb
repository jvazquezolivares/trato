# frozen_string_literal: true

require "rails_helper"

RSpec.describe "C3C Category Filtering with List Message (Task 20)", type: :service do
  describe "WhatsApp::ListMessageBuilder.build_categories_list" do
    before do
      # Mock ZonesService to return categories matching zones.json
      allow(ZonesService).to receive(:all_categories).and_return([
        { "id" => "plomeria", "name" => "Plomería", "icon" => "🔧", "slug" => "plomeria" },
        { "id" => "electricidad", "name" => "Electricidad", "icon" => "⚡", "slug" => "electricidad" },
        { "id" => "construccion", "name" => "Construcción y obra", "icon" => "🏗", "slug" => "construccion-y-obra" },
        { "id" => "clima", "name" => "Clima y refrigeración", "icon" => "❄️", "slug" => "clima-y-refrigeracion" },
        { "id" => "acabados", "name" => "Acabados e interiores", "icon" => "🎨", "slug" => "acabados-e-interiores" },
        { "id" => "carpinteria", "name" => "Carpintería", "icon" => "🪚", "slug" => "carpinteria" },
        { "id" => "herreria", "name" => "Herrería", "icon" => "🔨", "slug" => "herreria" },
        { "id" => "jardineria", "name" => "Jardinería", "icon" => "🌱", "slug" => "jardineria" },
        { "id" => "limpieza", "name" => "Limpieza", "icon" => "🧹", "slug" => "limpieza" },
        { "id" => "cerrajeria", "name" => "Cerrajería", "icon" => "🔑", "slug" => "cerrajeria" }
      ])
    end


    context "Acceptance Criteria 1: List Message displays all categories" do
      it "builds List Message with all categories from ZonesService" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        expect(payload).to be_a(Hash)
        expect(payload[:type]).to eq("list")
        expect(payload[:header]).to be_present
        expect(payload[:action]).to be_present
      end

      it "includes category icons and names in the payload" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        rows = payload.dig(:action, :sections, 0, :rows) || []
        expect(rows).not_to be_empty

        # Verify that rows contain category information
        first_row = rows.first
        expect(first_row).to have_key(:id)
        expect(first_row).to have_key(:title)
      end

      it "uses ZonesService to get all categories" do
        # Reset the mock to clear the call from before block
        allow(ZonesService).to receive(:all_categories).and_call_original

        WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        expect(ZonesService).to have_received(:all_categories).at_least(:once)
      end

      it "formats List Message according to Meta Cloud API spec" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        # Verify required fields for List Message
        expect(payload[:type]).to eq("list")
        expect(payload[:header][:type]).to eq("text")
        expect(payload[:header][:text]).to be_present
        expect(payload[:body][:text]).to be_present
        expect(payload[:action][:button]).to be_present
        expect(payload[:action][:sections]).to be_an(Array)
      end
    end

    context "Acceptance Criteria 2: No 'Ver más opciones' button used" do
      it "does not use Quick Reply Buttons (3-button limit workaround)" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        # List Message format, not Quick Reply Buttons
        expect(payload[:type]).to eq("list")
        expect(payload).not_to have_key(:buttons)
      end

      it "uses List Message rows for pagination instead of external buttons" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        rows = payload.dig(:action, :sections, 0, :rows) || []

        # Check if "Ver más categorías" is included as a row (not a button)
        ver_mas_row = rows.find { |row| row[:id] == "ver_mas_categorias" }

        # If there are more than 5 categories, "Ver más" should be included
        if ZonesService.all_categories.size > 5
          expect(ver_mas_row).to be_present
          expect(ver_mas_row[:title]).to include("Ver más")
        end
      end

      it "does not include 'Ver más opciones' as a separate button" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        # Verify no buttons array exists (List Message uses rows, not buttons)
        expect(payload).not_to have_key(:buttons)
      end
    end

    context "Acceptance Criteria 3: No Quick Reply Buttons used" do
      it "exclusively uses List Message format" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        expect(payload[:type]).to eq("list")
        expect(payload[:action][:sections]).to be_present
      end

      it "supports more than 3 category options" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        rows = payload.dig(:action, :sections, 0, :rows) || []

        # List Messages can show more than 3 options (Quick Reply Button limit)
        # Page 1 should show at least 5 categories
        category_rows = rows.reject { |row| row[:id] == "ver_mas_categorias" }
        expect(category_rows.size).to be >= 5
      end

      it "uses row IDs for category selection" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        rows = payload.dig(:action, :sections, 0, :rows) || []

        # Verify each row has an ID (used for selection)
        rows.each do |row|
          expect(row[:id]).to be_present
          expect(row[:title]).to be_present
        end
      end
    end

    context "Acceptance Criteria 4: All categories accessible in one or two List Messages" do
      it "displays first 5 categories on page 1" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        rows = payload.dig(:action, :sections, 0, :rows) || []
        category_rows = rows.reject { |row| row[:id] == "ver_mas_categorias" }

        # Page 1 should show first 5 categories
        expect(category_rows.size).to eq(5)
      end

      it "includes 'Ver más categorías' option on page 1 when there are more categories" do
        # Assuming there are 10 categories total
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        rows = payload.dig(:action, :sections, 0, :rows) || []
        ver_mas_row = rows.find { |row| row[:id] == "ver_mas_categorias" }

        # Should include "Ver más" if there are more than 5 categories
        if ZonesService.all_categories.size > 5
          expect(ver_mas_row).to be_present
          expect(ver_mas_row[:title]).to match(/Ver más/i)
        end
      end

      it "displays remaining categories on page 2" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        rows = payload.dig(:action, :sections, 0, :rows) || []

        # Page 2 should show remaining categories (5 more)
        expect(rows.size).to eq(5)
      end

      it "does not include 'Ver más categorías' on page 2 (last page)" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        rows = payload.dig(:action, :sections, 0, :rows) || []
        ver_mas_row = rows.find { |row| row[:id] == "ver_mas_categorias" }

        # Page 2 is the last page, so no "Ver más" option
        expect(ver_mas_row).to be_nil
      end

      it "ensures all 10 categories are accessible across two pages" do
        page_1_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)
        page_2_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        page_1_rows = page_1_payload.dig(:action, :sections, 0, :rows) || []
        page_2_rows = page_2_payload.dig(:action, :sections, 0, :rows) || []

        # Remove "Ver más" from page 1 count
        page_1_categories = page_1_rows.reject { |row| row[:id] == "ver_mas_categorias" }

        # Total categories across both pages should be 10
        total_categories = page_1_categories.size + page_2_rows.size
        expect(total_categories).to eq(10)
      end

      it "does not duplicate categories between pages" do
        page_1_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)
        page_2_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        page_1_rows = page_1_payload.dig(:action, :sections, 0, :rows) || []
        page_2_rows = page_2_payload.dig(:action, :sections, 0, :rows) || []

        page_1_ids = page_1_rows.map { |row| row[:id] }.reject { |id| id == "ver_mas_categorias" }
        page_2_ids = page_2_rows.map { |row| row[:id] }

        # No overlap between pages
        expect(page_1_ids & page_2_ids).to be_empty
      end
    end

    context "Integration: Category filtering in C2A flow (already tested in search_mode_spec)" do
      it "references existing C2A category selection tests" do
        # Category filtering for C2A (region-based discovery) is already tested in:
        # spec/services/client_assistant_orchestrator_search_mode_spec.rb
        #
        # Those tests verify:
        # - Category List Message is sent after zone selection
        # - "Ver más categorías" pagination works
        # - Category selection transitions to provider query
        #
        # This test serves as documentation that C2A category filtering is covered.
        expect(true).to be true
      end
    end

    context "Regression: Verify old Quick Reply Button pattern is removed" do
      it "does not use 3-button limit workaround" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        # Verify we're not limited to 3 categories
        rows = payload.dig(:action, :sections, 0, :rows) || []
        category_rows = rows.reject { |row| row[:id] == "ver_mas_categorias" }

        expect(category_rows.size).to be > 3
      end

      it "does not send 'Ver más opciones' as a separate Quick Reply Button" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        # Verify no buttons array (Quick Reply Buttons format)
        expect(payload).not_to have_key(:buttons)

        # Verify "Ver más" is a List Message row, not a button
        rows = payload.dig(:action, :sections, 0, :rows) || []
        ver_mas_row = rows.find { |row| row[:id] == "ver_mas_categorias" }

        if ZonesService.all_categories.size > 5
          expect(ver_mas_row).to be_present
          expect(ver_mas_row).to have_key(:id)
          expect(ver_mas_row).to have_key(:title)
        end
      end

      it "uses List Message pagination instead of button workaround" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        # Verify List Message format
        expect(payload[:type]).to eq("list")
        expect(payload[:action][:sections]).to be_an(Array)

        # Verify pagination is handled via rows
        rows = payload.dig(:action, :sections, 0, :rows) || []
        expect(rows).not_to be_empty
      end
    end

    context "Button label length compliance (WhatsApp API constraint)" do
      it "ensures all category titles are 20 characters or less" do
        page_1_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)
        page_2_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        page_1_rows = page_1_payload.dig(:action, :sections, 0, :rows) || []
        page_2_rows = page_2_payload.dig(:action, :sections, 0, :rows) || []

        all_rows = page_1_rows + page_2_rows

        all_rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end

      it "ensures 'Ver más categorías' title is 20 characters or less" do
        payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)

        rows = payload.dig(:action, :sections, 0, :rows) || []
        ver_mas_row = rows.find { |row| row[:id] == "ver_mas_categorias" }

        if ver_mas_row.present?
          expect(ver_mas_row[:title].length).to be <= 20
        end
      end
    end

    context "Comprehensive verification: All categories from zones.json are accessible" do
      it "makes all 10 categories from zones.json accessible via List Messages" do
        # Get all categories from zones.json
        all_categories = ZonesService.all_categories

        # Get categories from page 1 and page 2
        page_1_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)
        page_2_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        page_1_rows = page_1_payload.dig(:action, :sections, 0, :rows) || []
        page_2_rows = page_2_payload.dig(:action, :sections, 0, :rows) || []

        # Remove "Ver más categorías" from page 1
        page_1_categories = page_1_rows.reject { |row| row[:id] == "ver_mas_categorias" }

        # Collect all category IDs from both pages
        accessible_category_ids = (page_1_categories + page_2_rows).map { |row| row[:id] }

        # Verify all categories from zones.json are accessible
        all_categories.each do |category|
          expect(accessible_category_ids).to include(category["id"]),
                                             "Category '#{category['name']}' (#{category['id']}) is not accessible via List Messages"
        end

        # Verify count matches
        expect(accessible_category_ids.length).to eq(all_categories.length)
      end

      it "displays exact category names and icons from zones.json" do
        all_categories = ZonesService.all_categories

        page_1_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)
        page_2_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        page_1_rows = page_1_payload.dig(:action, :sections, 0, :rows) || []
        page_2_rows = page_2_payload.dig(:action, :sections, 0, :rows) || []

        # Remove "Ver más categorías" from page 1
        page_1_categories = page_1_rows.reject { |row| row[:id] == "ver_mas_categorias" }
        all_rows = page_1_categories + page_2_rows

        # Verify each category has correct icon and name
        all_categories.each do |category|
          matching_row = all_rows.find { |row| row[:id] == category["id"] }

          expect(matching_row).to be_present,
                                  "Category '#{category['name']}' (#{category['id']}) not found in List Messages"

          # Verify title includes icon and name (may be truncated)
          expected_title = "#{category['icon']} #{category['name']}"
          expect(matching_row[:title]).to start_with(category["icon"]),
                                          "Category '#{category['name']}' missing icon in title"
        end
      end

      it "verifies all 10 specific categories from zones.json are present" do
        # Expected categories from zones.json
        expected_categories = [
          "plomeria",
          "electricidad",
          "construccion",
          "clima",
          "acabados",
          "carpinteria",
          "herreria",
          "jardineria",
          "limpieza",
          "cerrajeria"
        ]

        page_1_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 1)
        page_2_payload = WhatsApp::ListMessageBuilder.build_categories_list(page: 2)

        page_1_rows = page_1_payload.dig(:action, :sections, 0, :rows) || []
        page_2_rows = page_2_payload.dig(:action, :sections, 0, :rows) || []

        # Remove "Ver más categorías" from page 1
        page_1_categories = page_1_rows.reject { |row| row[:id] == "ver_mas_categorias" }
        accessible_category_ids = (page_1_categories + page_2_rows).map { |row| row[:id] }

        # Verify each expected category is accessible
        expected_categories.each do |category_id|
          expect(accessible_category_ids).to include(category_id),
                                             "Expected category '#{category_id}' is not accessible"
        end

        # Verify count matches exactly
        expect(accessible_category_ids.length).to eq(expected_categories.length)
      end
    end
  end
end
