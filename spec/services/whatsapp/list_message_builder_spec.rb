# frozen_string_literal: true

require "rails_helper"

RSpec.describe WhatsApp::ListMessageBuilder do
  describe ".build_zones_list" do
    let(:zones) { ["Centro Histórico", "Boca del Río", "Costa Verde", "Mocambo"] }

    context "with default title" do
      it "returns a valid List Message payload" do
        result = described_class.build_zones_list(zones)

        expect(result).to be_a(Hash)
        expect(result[:type]).to eq("list")
      end

      it "includes header with default title" do
        result = described_class.build_zones_list(zones)

        expect(result[:header]).to eq({ type: "text", text: "Selecciona tu zona" })
      end

      it "includes body text" do
        result = described_class.build_zones_list(zones)

        expect(result[:body]).to eq({ text: "Elige la zona donde necesitas el servicio" })
      end

      it "includes action with button label" do
        result = described_class.build_zones_list(zones)

        expect(result[:action][:button]).to eq("Ver opciones")
      end

      it "includes sections with zones" do
        result = described_class.build_zones_list(zones)

        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].length).to eq(1)
      end

      it "includes section with title" do
        result = described_class.build_zones_list(zones)
        section = result[:action][:sections].first

        expect(section[:title]).to eq("Zonas disponibles")
      end

      it "includes rows with all zones" do
        result = described_class.build_zones_list(zones)
        rows = result[:action][:sections].first[:rows]

        expect(rows.length).to eq(4)
      end

      it "formats each zone as a row with id and title" do
        result = described_class.build_zones_list(zones)
        rows = result[:action][:sections].first[:rows]

        rows.each_with_index do |row, index|
          expect(row[:id]).to eq(zones[index])
          expect(row[:title]).to eq(zones[index])
        end
      end
    end

    context "with custom title" do
      it "uses the provided title in header" do
        custom_title = "Zonas en Veracruz"
        result = described_class.build_zones_list(zones, title: custom_title)

        expect(result[:header][:text]).to eq(custom_title)
      end

      it "maintains all other payload structure" do
        custom_title = "Zonas en Puebla"
        result = described_class.build_zones_list(zones, title: custom_title)

        expect(result[:type]).to eq("list")
        expect(result[:body]).to eq({ text: "Elige la zona donde necesitas el servicio" })
        expect(result[:action][:button]).to eq("Ver opciones")
      end
    end

    context "with empty zones array" do
      it "returns payload with empty rows" do
        result = described_class.build_zones_list([])
        rows = result[:action][:sections].first[:rows]

        expect(rows).to eq([])
      end

      it "maintains valid payload structure" do
        result = described_class.build_zones_list([])

        expect(result[:type]).to eq("list")
        expect(result[:header]).to be_present
        expect(result[:body]).to be_present
        expect(result[:action]).to be_present
      end
    end

    context "with single zone" do
      it "returns payload with one row" do
        single_zone = ["Centro Histórico"]
        result = described_class.build_zones_list(single_zone)
        rows = result[:action][:sections].first[:rows]

        expect(rows.length).to eq(1)
        expect(rows.first[:id]).to eq("Centro Histórico")
        expect(rows.first[:title]).to eq("Centro Histórico")
      end
    end

    context "with zones exceeding 20 characters" do
      it "truncates zone names to 20 characters" do
        long_zones = ["Zona Industrial Muy Larga Con Nombre Extenso"]
        result = described_class.build_zones_list(long_zones)
        rows = result[:action][:sections].first[:rows]

        expect(rows.first[:title].length).to be <= 20
        expect(rows.first[:title]).to end_with("…")
      end

      it "keeps zone id unchanged" do
        long_zones = ["Zona Industrial Muy Larga Con Nombre Extenso"]
        result = described_class.build_zones_list(long_zones)
        rows = result[:action][:sections].first[:rows]

        expect(rows.first[:id]).to eq("Zona Industrial Muy Larga Con Nombre Extenso")
      end

      it "truncates multiple long zone names" do
        long_zones = [
          "Zona Industrial Muy Larga Con Nombre Extenso",
          "Otra Zona Con Nombre Demasiado Largo Para WhatsApp"
        ]
        result = described_class.build_zones_list(long_zones)
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "with zones exactly 20 characters" do
      it "does not truncate zone names" do
        exact_zones = ["Exactamente20Chars!"]
        result = described_class.build_zones_list(exact_zones)
        rows = result[:action][:sections].first[:rows]

        expect(rows.first[:title]).to eq("Exactamente20Chars!")
        expect(rows.first[:title]).not_to end_with("…")
      end
    end

    context "with zones under 20 characters" do
      it "keeps zone names unchanged" do
        short_zones = ["Centro", "Norte", "Sur"]
        result = described_class.build_zones_list(short_zones)
        rows = result[:action][:sections].first[:rows]

        expect(rows[0][:title]).to eq("Centro")
        expect(rows[1][:title]).to eq("Norte")
        expect(rows[2][:title]).to eq("Sur")
      end
    end

    context "with special characters in zone names" do
      it "preserves special characters" do
        special_zones = ["Zona 1 & 2", "Área #3", "Sector (A)"]
        result = described_class.build_zones_list(special_zones)
        rows = result[:action][:sections].first[:rows]

        expect(rows[0][:title]).to eq("Zona 1 & 2")
        expect(rows[1][:title]).to eq("Área #3")
        expect(rows[2][:title]).to eq("Sector (A)")
      end
    end

    context "with accented characters in zone names" do
      it "preserves accented characters" do
        accented_zones = ["Histórico", "Revolución", "México"]
        result = described_class.build_zones_list(accented_zones)
        rows = result[:action][:sections].first[:rows]

        expect(rows[0][:title]).to eq("Histórico")
        expect(rows[1][:title]).to eq("Revolución")
        expect(rows[2][:title]).to eq("México")
      end
    end

    context "Meta Cloud API compliance" do
      it "returns payload matching Meta Cloud API List Message format" do
        result = described_class.build_zones_list(zones)

        # Verify top-level structure
        expect(result).to have_key(:type)
        expect(result).to have_key(:header)
        expect(result).to have_key(:body)
        expect(result).to have_key(:action)

        # Verify header structure
        expect(result[:header]).to have_key(:type)
        expect(result[:header]).to have_key(:text)

        # Verify body structure
        expect(result[:body]).to have_key(:text)

        # Verify action structure
        expect(result[:action]).to have_key(:button)
        expect(result[:action]).to have_key(:sections)

        # Verify sections structure
        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].first).to have_key(:title)
        expect(result[:action][:sections].first).to have_key(:rows)

        # Verify rows structure
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character button label limit" do
        result = described_class.build_zones_list(zones)

        expect(result[:action][:button].length).to be <= 20
      end

      it "respects 20-character row title limit" do
        long_zones = ["A" * 50, "B" * 50]
        result = described_class.build_zones_list(long_zones)
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "integration with ZonesService" do
      it "works with zones from ZonesService.zones_for_state" do
        veracruz_zones = ZonesService.zones_for_state("Veracruz")
        result = described_class.build_zones_list(veracruz_zones)

        expect(result[:type]).to eq("list")
        expect(result[:action][:sections].first[:rows].length).to eq(veracruz_zones.length)
      end

      it "works with zones from ZonesService.all_zones" do
        all_zones = ZonesService.all_zones
        result = described_class.build_zones_list(all_zones)

        expect(result[:type]).to eq("list")
        expect(result[:action][:sections].first[:rows].length).to eq(all_zones.length)
      end
    end
  end

  describe ".build_categories_list" do
    context "with page 1" do
      it "returns a valid List Message payload" do
        result = described_class.build_categories_list(page: 1)

        expect(result).to be_a(Hash)
        expect(result[:type]).to eq("list")
      end

      it "includes header with title" do
        result = described_class.build_categories_list(page: 1)

        expect(result[:header]).to eq({ type: "text", text: "¿Qué tipo de técnico?" })
      end

      it "includes body text" do
        result = described_class.build_categories_list(page: 1)

        expect(result[:body]).to eq({ text: "Selecciona el servicio que necesitas" })
      end

      it "includes action with button label" do
        result = described_class.build_categories_list(page: 1)

        expect(result[:action][:button]).to eq("Ver opciones")
      end

      it "includes sections with categories" do
        result = described_class.build_categories_list(page: 1)

        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].length).to eq(1)
      end

      it "includes section with title" do
        result = described_class.build_categories_list(page: 1)
        section = result[:action][:sections].first

        expect(section[:title]).to eq("Categorías")
      end

      it "includes first 5 categories from ZonesService plus 'Ver más' option" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        # Page 1 should have 5 categories + "Ver más categorías" = 6 rows
        expect(rows.length).to eq(6)

        # Last row should be "Ver más categorías"
        expect(rows.last[:id]).to eq("ver_mas_categorias")
        expect(rows.last[:title]).to eq("Ver más categorías")
      end

      it "formats each category with icon and name (except 'Ver más' option)" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        # Check first 5 rows (actual categories) have emoji icons
        rows.first(5).each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
          expect(row[:title]).to match(/\p{Emoji}/) # Contains emoji icon
        end

        # Last row is "Ver más categorías" (no emoji required)
        expect(rows.last[:id]).to eq("ver_mas_categorias")
      end

      it "uses category id as row id (for first 5 categories)" do
        categories = ZonesService.categories_page(1)
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        # Check first 5 rows match category IDs
        rows.first(5).each_with_index do |row, index|
          expect(row[:id]).to eq(categories[index]["id"])
        end

        # Last row should be "ver_mas_categorias"
        expect(rows.last[:id]).to eq("ver_mas_categorias")
      end

      it "respects 20-character title limit" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "with page 2" do
      it "returns a valid List Message payload" do
        result = described_class.build_categories_list(page: 2)

        expect(result).to be_a(Hash)
        expect(result[:type]).to eq("list")
      end

      it "includes remaining categories after first 5" do
        all_categories = ZonesService.all_categories
        result = described_class.build_categories_list(page: 2)
        rows = result[:action][:sections].first[:rows]

        expected_count = [all_categories.length - 5, 0].max
        expect(rows.length).to eq(expected_count)
      end

      it "uses same header and body as page 1" do
        result = described_class.build_categories_list(page: 2)

        expect(result[:header][:text]).to eq("¿Qué tipo de técnico?")
        expect(result[:body][:text]).to eq("Selecciona el servicio que necesitas")
      end

      it "formats categories with icon and name" do
        result = described_class.build_categories_list(page: 2)
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character title limit" do
        result = described_class.build_categories_list(page: 2)
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "Meta Cloud API compliance" do
      it "returns payload matching Meta Cloud API List Message format" do
        result = described_class.build_categories_list(page: 1)

        # Verify top-level structure
        expect(result).to have_key(:type)
        expect(result).to have_key(:header)
        expect(result).to have_key(:body)
        expect(result).to have_key(:action)

        # Verify header structure
        expect(result[:header]).to have_key(:type)
        expect(result[:header]).to have_key(:text)

        # Verify body structure
        expect(result[:body]).to have_key(:text)

        # Verify action structure
        expect(result[:action]).to have_key(:button)
        expect(result[:action]).to have_key(:sections)

        # Verify sections structure
        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].first).to have_key(:title)
        expect(result[:action][:sections].first).to have_key(:rows)

        # Verify rows structure
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character button label limit" do
        result = described_class.build_categories_list(page: 1)

        expect(result[:action][:button].length).to be <= 20
      end

      it "respects 20-character row title limit for all pages" do
        [1, 2].each do |page|
          result = described_class.build_categories_list(page: page)
          rows = result[:action][:sections].first[:rows]

          rows.each do |row|
            expect(row[:title].length).to be <= 20
          end
        end
      end
    end

    context "integration with ZonesService" do
      it "uses categories from ZonesService.categories_page plus 'Ver más' option" do
        page_1_categories = ZonesService.categories_page(1)
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        # Page 1 should have 5 categories + "Ver más" = 6 rows
        expect(rows.length).to eq(page_1_categories.length + 1)

        # First 5 rows should match categories
        rows.first(5).each_with_index do |row, index|
          expect(row[:id]).to eq(page_1_categories[index]["id"])
        end

        # Last row should be "Ver más categorías"
        expect(rows.last[:id]).to eq("ver_mas_categorias")
      end

      it "handles pagination correctly (5 categories + 'Ver más' on page 1, remaining on page 2)" do
        all_categories = ZonesService.all_categories

        page_1_result = described_class.build_categories_list(page: 1)
        page_1_rows = page_1_result[:action][:sections].first[:rows]

        page_2_result = described_class.build_categories_list(page: 2)
        page_2_rows = page_2_result[:action][:sections].first[:rows]

        # Page 1 has 5 categories + "Ver más" = 6 rows
        # Page 2 has remaining categories (no "Ver más")
        # Total unique categories = page_1_rows - 1 (exclude "Ver más") + page_2_rows
        total_category_rows = (page_1_rows.length - 1) + page_2_rows.length
        expect(total_category_rows).to eq(all_categories.length)
      end

      it "does not duplicate categories across pages" do
        page_1_result = described_class.build_categories_list(page: 1)
        page_1_ids = page_1_result[:action][:sections].first[:rows].map { |r| r[:id] }

        page_2_result = described_class.build_categories_list(page: 2)
        page_2_ids = page_2_result[:action][:sections].first[:rows].map { |r| r[:id] }

        expect(page_1_ids & page_2_ids).to be_empty
      end
    end

    context "with expected categories from requirements" do
      it "includes Plomería in page 1" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        plomeria = rows.find { |r| r[:title].include?("Plomería") }
        expect(plomeria).to be_present
        expect(plomeria[:title]).to include("🔧")
      end

      it "includes Electricidad in page 1" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        electricidad = rows.find { |r| r[:title].include?("Electricidad") }
        expect(electricidad).to be_present
        expect(electricidad[:title]).to include("⚡")
      end

      it "includes Construcción y obra in page 1" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        construccion = rows.find { |r| r[:title].include?("Construcción") }
        expect(construccion).to be_present
        expect(construccion[:title]).to include("🏗")
      end

      it "includes Clima y refrigeración in page 1" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        clima = rows.find { |r| r[:title].include?("Clima") }
        expect(clima).to be_present
        expect(clima[:title]).to include("❄️")
      end

      it "includes Acabados e interiores in page 1" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        acabados = rows.find { |r| r[:title].include?("Acabados") }
        expect(acabados).to be_present
        expect(acabados[:title]).to include("🎨")
      end
    end
  end

  describe ".build_experience_range_list" do
    it "returns a valid List Message payload" do
      result = described_class.build_experience_range_list

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("list")
    end

    it "includes header with title" do
      result = described_class.build_experience_range_list

      expect(result[:header]).to eq({ type: "text", text: "Años de experiencia" })
    end

    it "includes body text" do
      result = described_class.build_experience_range_list

      expect(result[:body]).to eq({ text: "¿Cuántos años llevas trabajando en tu oficio?" })
    end

    it "includes action with button label" do
      result = described_class.build_experience_range_list

      expect(result[:action][:button]).to eq("Ver opciones")
    end

    it "includes sections with experience ranges" do
      result = described_class.build_experience_range_list

      expect(result[:action][:sections]).to be_an(Array)
      expect(result[:action][:sections].length).to eq(1)
    end

    it "includes section with title" do
      result = described_class.build_experience_range_list
      section = result[:action][:sections].first

      expect(section[:title]).to eq("Experiencia")
    end

    it "includes exactly 4 experience range options" do
      result = described_class.build_experience_range_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.length).to eq(4)
    end

    it "includes correct experience range options" do
      result = described_class.build_experience_range_list
      rows = result[:action][:sections].first[:rows]

      expect(rows[0]).to eq({ id: "1-3", title: "1–3 años" })
      expect(rows[1]).to eq({ id: "4-6", title: "4–6 años" })
      expect(rows[2]).to eq({ id: "7-10", title: "7–10 años" })
      expect(rows[3]).to eq({ id: "10+", title: "Más de 10 años" })
    end

    it "formats each experience range with id and title" do
      result = described_class.build_experience_range_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row).to have_key(:id)
        expect(row).to have_key(:title)
        expect(row[:title]).to include("años")
      end
    end

    it "respects 20-character title limit" do
      result = described_class.build_experience_range_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row[:title].length).to be <= 20
      end
    end

    context "Meta Cloud API compliance" do
      it "returns payload matching Meta Cloud API List Message format" do
        result = described_class.build_experience_range_list

        # Verify top-level structure
        expect(result).to have_key(:type)
        expect(result).to have_key(:header)
        expect(result).to have_key(:body)
        expect(result).to have_key(:action)

        # Verify header structure
        expect(result[:header]).to have_key(:type)
        expect(result[:header]).to have_key(:text)

        # Verify body structure
        expect(result[:body]).to have_key(:text)

        # Verify action structure
        expect(result[:action]).to have_key(:button)
        expect(result[:action]).to have_key(:sections)

        # Verify sections structure
        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].first).to have_key(:title)
        expect(result[:action][:sections].first).to have_key(:rows)

        # Verify rows structure
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character button label limit" do
        result = described_class.build_experience_range_list

        expect(result[:action][:button].length).to be <= 20
      end

      it "respects 20-character row title limit" do
        result = described_class.build_experience_range_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "requirement compliance" do
      it "matches Requirement 7 acceptance criteria" do
        result = described_class.build_experience_range_list

        # AC1: List Message with title "Años de experiencia"
        expect(result[:header][:text]).to eq("Años de experiencia")

        # AC2: Exactly four options with correct values
        rows = result[:action][:sections].first[:rows]
        expect(rows.length).to eq(4)
        expect(rows.map { |r| r[:title] }).to eq([
          "1–3 años",
          "4–6 años",
          "7–10 años",
          "Más de 10 años"
        ])
      end

      it "provides unique ids for each experience range" do
        result = described_class.build_experience_range_list
        rows = result[:action][:sections].first[:rows]
        ids = rows.map { |r| r[:id] }

        expect(ids.uniq.length).to eq(4)
        expect(ids).to eq(["1-3", "4-6", "7-10", "10+"])
      end

      it "provides ids that can be mapped to numeric values" do
        result = described_class.build_experience_range_list
        rows = result[:action][:sections].first[:rows]

        # Verify ids match the mapping pattern from Requirement 5.1
        # "1–3 años" → 1, "4–6 años" → 4, "7–10 años" → 7, "Más de 10 años" → 10
        expect(rows[0][:id]).to eq("1-3")   # Maps to 1
        expect(rows[1][:id]).to eq("4-6")   # Maps to 4
        expect(rows[2][:id]).to eq("7-10")  # Maps to 7
        expect(rows[3][:id]).to eq("10+")   # Maps to 10
      end
    end
  end

  describe ".build_decline_reasons_list" do
    it "returns a valid List Message payload" do
      result = described_class.build_decline_reasons_list

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("list")
    end

    it "includes header with title" do
      result = described_class.build_decline_reasons_list

      expect(result[:header]).to eq({ type: "text", text: "¿Por qué no por ahora?" })
    end

    it "includes body text" do
      result = described_class.build_decline_reasons_list

      expect(result[:body]).to eq({ text: "Me ayudaría saber qué te detiene" })
    end

    it "includes action with button label" do
      result = described_class.build_decline_reasons_list

      expect(result[:action][:button]).to eq("Ver opciones")
    end

    it "includes sections with decline reasons" do
      result = described_class.build_decline_reasons_list

      expect(result[:action][:sections]).to be_an(Array)
      expect(result[:action][:sections].length).to eq(1)
    end

    it "includes section with title" do
      result = described_class.build_decline_reasons_list
      section = result[:action][:sections].first

      expect(section[:title]).to eq("Razón")
    end

    it "includes exactly 6 decline reason options" do
      result = described_class.build_decline_reasons_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.length).to eq(6)
    end

    it "includes correct decline reason ids" do
      result = described_class.build_decline_reasons_list
      rows = result[:action][:sections].first[:rows]

      expect(rows[0][:id]).to eq("busy")
      expect(rows[1][:id]).to eq("dont_understand")
      expect(rows[2][:id]).to eq("not_worth_it")
      expect(rows[3][:id]).to eq("uncomfortable_whatsapp")
      expect(rows[4][:id]).to eq("enough_clients")
      expect(rows[5][:id]).to eq("other")
    end

    it "truncates titles that exceed 20 characters" do
      result = described_class.build_decline_reasons_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row[:title].length).to be <= 20
      end
    end

    it "formats each decline reason with id and title" do
      result = described_class.build_decline_reasons_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row).to have_key(:id)
        expect(row).to have_key(:title)
        expect(row[:title]).to be_a(String)
        expect(row[:title]).not_to be_empty
      end
    end

    it "includes 'Otro motivo' as the last option" do
      result = described_class.build_decline_reasons_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.last[:id]).to eq("other")
      expect(rows.last[:title]).to eq("Otro motivo")
    end

    context "Meta Cloud API compliance" do
      it "returns payload matching Meta Cloud API List Message format" do
        result = described_class.build_decline_reasons_list

        # Verify top-level structure
        expect(result).to have_key(:type)
        expect(result).to have_key(:header)
        expect(result).to have_key(:body)
        expect(result).to have_key(:action)

        # Verify header structure
        expect(result[:header]).to have_key(:type)
        expect(result[:header]).to have_key(:text)

        # Verify body structure
        expect(result[:body]).to have_key(:text)

        # Verify action structure
        expect(result[:action]).to have_key(:button)
        expect(result[:action]).to have_key(:sections)

        # Verify sections structure
        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].first).to have_key(:title)
        expect(result[:action][:sections].first).to have_key(:rows)

        # Verify rows structure
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character button label limit" do
        result = described_class.build_decline_reasons_list

        expect(result[:action][:button].length).to be <= 20
      end

      it "respects 20-character row title limit" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "requirement compliance" do
      it "matches Requirement 4 acceptance criteria" do
        result = described_class.build_decline_reasons_list

        # AC1: List Message with title "¿Por qué no por ahora?" and six reason options
        expect(result[:header][:text]).to eq("¿Por qué no por ahora?")

        rows = result[:action][:sections].first[:rows]
        expect(rows.length).to eq(6)
      end

      it "includes all required decline reasons from requirements" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]

        # Extract titles (shortened to fit 20-char limit)
        titles = rows.map { |r| r[:title] }

        # Verify each required reason is present (using shortened versions)
        expect(titles.any? { |t| t.start_with?("Estoy muy ocupado") }).to be true
        expect(titles.any? { |t| t.start_with?("No entiendo") }).to be true
        expect(titles.any? { |t| t.start_with?("No sé si vale") }).to be true
        expect(titles.any? { |t| t.start_with?("No me gusta") }).to be true
        expect(titles.any? { |t| t.start_with?("Tengo suficientes") }).to be true
        expect(titles.any? { |t| t == "Otro motivo" }).to be true
      end

      it "provides unique ids for each decline reason" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]
        ids = rows.map { |r| r[:id] }

        expect(ids.uniq.length).to eq(6)
        expect(ids).to eq(["busy", "dont_understand", "not_worth_it", "uncomfortable_whatsapp", "enough_clients", "other"])
      end
    end

    context "truncation behavior" do
      it "verifies 'Estoy muy ocupado' fits within 20 characters" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]
        busy_row = rows.find { |r| r[:id] == "busy" }

        expect(busy_row[:title]).to eq("Estoy muy ocupado")
        expect(busy_row[:title].length).to be <= 20
      end

      it "verifies 'No entiendo qué es' fits within 20 characters" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]
        understand_row = rows.find { |r| r[:id] == "dont_understand" }

        expect(understand_row[:title]).to eq("No entiendo qué es")
        expect(understand_row[:title].length).to be <= 20
      end

      it "verifies 'No sé si vale pena' fits within 20 characters" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]
        worth_row = rows.find { |r| r[:id] == "not_worth_it" }

        expect(worth_row[:title]).to eq("No sé si vale pena")
        expect(worth_row[:title].length).to be <= 20
      end

      it "verifies 'No me gusta WhatsApp' fits within 20 characters" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]
        uncomfortable_row = rows.find { |r| r[:id] == "uncomfortable_whatsapp" }

        expect(uncomfortable_row[:title]).to eq("No me gusta WhatsApp")
        expect(uncomfortable_row[:title].length).to be <= 20
      end

      it "verifies 'Tengo suficientes' fits within 20 characters" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]
        clients_row = rows.find { |r| r[:id] == "enough_clients" }

        expect(clients_row[:title]).to eq("Tengo suficientes")
        expect(clients_row[:title].length).to be <= 20
      end

      it "does not truncate 'Otro motivo' as it fits within 20 characters" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]
        other_row = rows.find { |r| r[:id] == "other" }

        expect(other_row[:title]).to eq("Otro motivo")
        expect(other_row[:title]).not_to end_with("…")
        expect(other_row[:title].length).to be < 20
      end
    end

    context "integration with provider onboarding flow" do
      it "can be used in P1B decline flow" do
        result = described_class.build_decline_reasons_list

        # Verify the payload is ready to be sent via WhatsApp service
        expect(result[:type]).to eq("list")
        expect(result[:action][:sections].first[:rows].length).to eq(6)

        # Verify all ids are suitable for database storage
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row[:id]).to be_a(String)
          expect(row[:id]).to match(/^[a-z_]+$/)
        end
      end

      it "provides ids that can be stored in providers.decline_reason column" do
        result = described_class.build_decline_reasons_list
        rows = result[:action][:sections].first[:rows]

        # All ids should be valid strings for database storage
        rows.each do |row|
          expect(row[:id]).to be_a(String)
          expect(row[:id].length).to be > 0
          expect(row[:id].length).to be < 255 # Typical string column limit
        end
      end
    end
  end

  describe ".build_categories_list with 'Ver más categorías' option" do
    context "when there are more than 5 categories" do
      before do
        # Ensure we have more than 5 categories in zones.json
        all_categories = ZonesService.all_categories
        skip "Test requires more than 5 categories in zones.json" if all_categories.length <= 5
      end

      it "includes 'Ver más categorías' option on page 1" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        # Should have 5 categories + 1 "Ver más" option = 6 rows
        expect(rows.length).to eq(6)

        # Last row should be "Ver más categorías"
        ver_mas_option = rows.last
        expect(ver_mas_option[:id]).to eq("ver_mas_categorias")
        expect(ver_mas_option[:title]).to eq("Ver más categorías")
      end

      it "does not include 'Ver más categorías' option on page 2" do
        result = described_class.build_categories_list(page: 2)
        rows = result[:action][:sections].first[:rows]

        # Should not have "Ver más" option on page 2
        ver_mas_option = rows.find { |r| r[:id] == "ver_mas_categorias" }
        expect(ver_mas_option).to be_nil
      end

      it "respects 20-character limit for 'Ver más categorías'" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        ver_mas_option = rows.last
        expect(ver_mas_option[:title].length).to be <= 20
      end
    end

    context "when there are exactly 5 or fewer categories" do
      before do
        # Mock ZonesService to return exactly 5 categories
        allow(ZonesService).to receive(:all_categories).and_return([
          { "id" => "cat1", "name" => "Category 1", "icon" => "🔧" },
          { "id" => "cat2", "name" => "Category 2", "icon" => "⚡" },
          { "id" => "cat3", "name" => "Category 3", "icon" => "🏗" },
          { "id" => "cat4", "name" => "Category 4", "icon" => "❄️" },
          { "id" => "cat5", "name" => "Category 5", "icon" => "🎨" }
        ])
        allow(ZonesService).to receive(:categories_page).and_call_original
      end

      it "does not include 'Ver más categorías' option on page 1" do
        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        # Should have exactly 5 rows (no "Ver más" option)
        expect(rows.length).to eq(5)

        # Should not have "Ver más" option
        ver_mas_option = rows.find { |r| r[:id] == "ver_mas_categorias" }
        expect(ver_mas_option).to be_nil
      end
    end

    context "requirement compliance for C2A flow" do
      it "matches Requirement 9 acceptance criteria for page 1" do
        all_categories = ZonesService.all_categories
        skip "Test requires more than 5 categories" if all_categories.length <= 5

        result = described_class.build_categories_list(page: 1)
        rows = result[:action][:sections].first[:rows]

        # AC7: Category List Message includes first 5 + "Ver más categorías"
        expect(rows.length).to eq(6)

        # Verify first 5 are actual categories
        rows[0..4].each do |row|
          expect(row[:id]).not_to eq("ver_mas_categorias")
          expect(row[:title]).to match(/\p{Emoji}/) # Contains emoji
        end

        # Verify last is "Ver más categorías"
        expect(rows.last[:id]).to eq("ver_mas_categorias")
        expect(rows.last[:title]).to eq("Ver más categorías")
      end

      it "matches Requirement 9 acceptance criteria for page 2" do
        all_categories = ZonesService.all_categories
        skip "Test requires more than 5 categories" if all_categories.length <= 5

        result = described_class.build_categories_list(page: 2)
        rows = result[:action][:sections].first[:rows]

        # AC8: Page 2 shows remaining categories (no "Ver más")
        expect(rows.length).to eq(all_categories.length - 5)

        # Verify none are "Ver más categorías"
        rows.each do |row|
          expect(row[:id]).not_to eq("ver_mas_categorias")
        end
      end
    end
  end

  describe ".build_price_range_list" do
    it "returns a valid List Message payload" do
      result = described_class.build_price_range_list

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("list")
    end

    it "includes header with title" do
      result = described_class.build_price_range_list

      expect(result[:header]).to eq({ type: "text", text: "Rango de precio" })
    end

    it "includes body text" do
      result = described_class.build_price_range_list

      expect(result[:body]).to eq({ text: "¿Cuánto cobras por una visita de diagnóstico?" })
    end

    it "includes action with button label" do
      result = described_class.build_price_range_list

      expect(result[:action][:button]).to eq("Ver opciones")
    end

    it "includes sections with price ranges" do
      result = described_class.build_price_range_list

      expect(result[:action][:sections]).to be_an(Array)
      expect(result[:action][:sections].length).to eq(1)
    end

    it "includes section with title" do
      result = described_class.build_price_range_list
      section = result[:action][:sections].first

      expect(section[:title]).to eq("Precio de diagnóstico")
    end

    it "includes exactly 4 price range options" do
      result = described_class.build_price_range_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.length).to eq(4)
    end

    it "includes correct price range options" do
      result = described_class.build_price_range_list
      rows = result[:action][:sections].first[:rows]

      expect(rows[0]).to eq({ id: "100-200", title: "$100–200 MXN" })
      expect(rows[1]).to eq({ id: "200-400", title: "$200–400 MXN" })
      expect(rows[2]).to eq({ id: "400-600", title: "$400–600 MXN" })
      expect(rows[3]).to eq({ id: "600+", title: "Más de $600 MXN" })
    end

    it "formats each price range with id and title" do
      result = described_class.build_price_range_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row).to have_key(:id)
        expect(row).to have_key(:title)
        expect(row[:title]).to include("MXN")
      end
    end

    it "respects 20-character title limit" do
      result = described_class.build_price_range_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row[:title].length).to be <= 20
      end
    end

    context "Meta Cloud API compliance" do
      it "returns payload matching Meta Cloud API List Message format" do
        result = described_class.build_price_range_list

        # Verify top-level structure
        expect(result).to have_key(:type)
        expect(result).to have_key(:header)
        expect(result).to have_key(:body)
        expect(result).to have_key(:action)

        # Verify header structure
        expect(result[:header]).to have_key(:type)
        expect(result[:header]).to have_key(:text)

        # Verify body structure
        expect(result[:body]).to have_key(:text)

        # Verify action structure
        expect(result[:action]).to have_key(:button)
        expect(result[:action]).to have_key(:sections)

        # Verify sections structure
        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].first).to have_key(:title)
        expect(result[:action][:sections].first).to have_key(:rows)

        # Verify rows structure
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character button label limit" do
        result = described_class.build_price_range_list

        expect(result[:action][:button].length).to be <= 20
      end

      it "respects 20-character row title limit" do
        result = described_class.build_price_range_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "requirement compliance" do
      it "matches Requirement 6 acceptance criteria" do
        result = described_class.build_price_range_list

        # AC1: List Message with title "Rango de precio"
        expect(result[:header][:text]).to eq("Rango de precio")

        # AC2: Exactly four options with correct values
        rows = result[:action][:sections].first[:rows]
        expect(rows.length).to eq(4)
        expect(rows.map { |r| r[:title] }).to eq([
          "$100–200 MXN",
          "$200–400 MXN",
          "$400–600 MXN",
          "Más de $600 MXN"
        ])
      end

      it "provides unique ids for each price range" do
        result = described_class.build_price_range_list
        rows = result[:action][:sections].first[:rows]
        ids = rows.map { |r| r[:id] }

        expect(ids.uniq.length).to eq(4)
        expect(ids).to eq(["100-200", "200-400", "400-600", "600+"])
      end
    end
  end

  describe ".build_financial_options_list" do
    it "returns a valid List Message payload" do
      result = described_class.build_financial_options_list

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("list")
    end

    it "includes header with title" do
      result = described_class.build_financial_options_list

      expect(result[:header]).to eq({ type: "text", text: "¿Qué quieres ver?" })
    end

    it "includes body text" do
      result = described_class.build_financial_options_list

      expect(result[:body]).to eq({ text: "Puedo mostrarte un resumen de tus finanzas" })
    end

    it "includes action with button label" do
      result = described_class.build_financial_options_list

      expect(result[:action][:button]).to eq("Ver opciones")
    end

    it "includes sections with financial options" do
      result = described_class.build_financial_options_list

      expect(result[:action][:sections]).to be_an(Array)
      expect(result[:action][:sections].length).to eq(1)
    end

    it "includes section with title" do
      result = described_class.build_financial_options_list
      section = result[:action][:sections].first

      expect(section[:title]).to eq("Opciones financieras")
    end

    it "includes exactly 4 financial options" do
      result = described_class.build_financial_options_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.length).to eq(4)
    end

    it "includes correct financial options" do
      result = described_class.build_financial_options_list
      rows = result[:action][:sections].first[:rows]

      expect(rows[0][:id]).to eq("income")
      expect(rows[0][:title]).to eq("Ver ingresos")

      expect(rows[1][:id]).to eq("expenses")
      expect(rows[1][:title]).to eq("Ver gastos")

      expect(rows[2][:id]).to eq("pending")
      expect(rows[2][:title]).to eq("Ver cobros") # Shortened to fit 20-char limit

      expect(rows[3][:id]).to eq("no_thanks")
      expect(rows[3][:title]).to eq("No, gracias")
    end

    it "formats each financial option with id and title" do
      result = described_class.build_financial_options_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row).to have_key(:id)
        expect(row).to have_key(:title)
        expect(row[:title]).to be_a(String)
        expect(row[:title]).not_to be_empty
      end
    end

    it "respects 20-character title limit" do
      result = described_class.build_financial_options_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row[:title].length).to be <= 20
      end
    end

    it "includes 'No, gracias' as the last option" do
      result = described_class.build_financial_options_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.last[:id]).to eq("no_thanks")
      expect(rows.last[:title]).to eq("No, gracias")
    end

    context "Meta Cloud API compliance" do
      it "returns payload matching Meta Cloud API List Message format" do
        result = described_class.build_financial_options_list

        # Verify top-level structure
        expect(result).to have_key(:type)
        expect(result).to have_key(:header)
        expect(result).to have_key(:body)
        expect(result).to have_key(:action)

        # Verify header structure
        expect(result[:header]).to have_key(:type)
        expect(result[:header]).to have_key(:text)

        # Verify body structure
        expect(result[:body]).to have_key(:text)

        # Verify action structure
        expect(result[:action]).to have_key(:button)
        expect(result[:action]).to have_key(:sections)

        # Verify sections structure
        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].first).to have_key(:title)
        expect(result[:action][:sections].first).to have_key(:rows)

        # Verify rows structure
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character button label limit" do
        result = described_class.build_financial_options_list

        expect(result[:action][:button].length).to be <= 20
      end

      it "respects 20-character row title limit" do
        result = described_class.build_financial_options_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "requirement compliance" do
      it "matches Requirement 8 acceptance criteria" do
        result = described_class.build_financial_options_list

        # AC1: List Message with title "¿Qué quieres ver?"
        expect(result[:header][:text]).to eq("¿Qué quieres ver?")

        # AC2: Exactly four options (titles may be truncated for API compliance)
        rows = result[:action][:sections].first[:rows]
        expect(rows.length).to eq(4)

        # Verify option ids match requirements
        expect(rows.map { |r| r[:id] }).to eq(["income", "expenses", "pending", "no_thanks"])
      end

      it "provides unique ids for each financial option" do
        result = described_class.build_financial_options_list
        rows = result[:action][:sections].first[:rows]
        ids = rows.map { |r| r[:id] }

        expect(ids.uniq.length).to eq(4)
        expect(ids).to eq(["income", "expenses", "pending", "no_thanks"])
      end

      it "provides ids that can be used for routing to financial queries" do
        result = described_class.build_financial_options_list
        rows = result[:action][:sections].first[:rows]

        # Verify ids are suitable for routing logic
        rows.each do |row|
          expect(row[:id]).to be_a(String)
          expect(row[:id]).to match(/^[a-z_]+$/)
        end
      end
    end

    context "integration with provider flows" do
      it "can be used in P17 financial summary flow" do
        result = described_class.build_financial_options_list

        # Verify the payload is ready to be sent via WhatsApp service
        expect(result[:type]).to eq("list")
        expect(result[:action][:sections].first[:rows].length).to eq(4)

        # Verify all ids are suitable for routing to financial queries
        rows = result[:action][:sections].first[:rows]
        expect(rows.map { |r| r[:id] }).to include("income", "expenses", "pending")
      end

      it "includes opt-out option for providers who don't want financial info" do
        result = described_class.build_financial_options_list
        rows = result[:action][:sections].first[:rows]

        no_thanks_option = rows.find { |r| r[:id] == "no_thanks" }
        expect(no_thanks_option).to be_present
        expect(no_thanks_option[:title]).to eq("No, gracias")
      end
    end

    context "title length validation" do
      it "truncates titles that exceed 20 characters" do
        result = described_class.build_financial_options_list
        rows = result[:action][:sections].first[:rows]

        # All titles should be 20 characters or less
        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end

      it "verifies 'Ver cobros' fits within 20-character limit" do
        result = described_class.build_financial_options_list
        rows = result[:action][:sections].first[:rows]
        pending_row = rows.find { |r| r[:id] == "pending" }

        expect(pending_row[:title]).to eq("Ver cobros")
        expect(pending_row[:title].length).to be <= 20
      end

      it "does not truncate titles under 20 characters" do
        result = described_class.build_financial_options_list
        rows = result[:action][:sections].first[:rows]

        short_titles = rows.select { |r| ["income", "expenses", "no_thanks"].include?(r[:id]) }
        short_titles.each do |row|
          expect(row[:title]).not_to end_with("…")
        end
      end
    end
  end

  describe ".build_rating_list" do
    it "returns a valid List Message payload" do
      result = described_class.build_rating_list

      expect(result).to be_a(Hash)
      expect(result[:type]).to eq("list")
    end

    it "includes header with title" do
      result = described_class.build_rating_list

      expect(result[:header]).to eq({ type: "text", text: "¿Cómo calificarías el trabajo?" })
    end

    it "includes body text" do
      result = described_class.build_rating_list

      expect(result[:body]).to eq({ text: "Tu opinión ayuda a otros clientes" })
    end

    it "includes action with button label" do
      result = described_class.build_rating_list

      expect(result[:action][:button]).to eq("Ver opciones")
    end

    it "includes sections with rating options" do
      result = described_class.build_rating_list

      expect(result[:action][:sections]).to be_an(Array)
      expect(result[:action][:sections].length).to eq(1)
    end

    it "includes section with title" do
      result = described_class.build_rating_list
      section = result[:action][:sections].first

      expect(section[:title]).to eq("Calificación")
    end

    it "includes exactly 5 star rating options" do
      result = described_class.build_rating_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.length).to eq(5)
    end

    it "includes correct star rating options in descending order" do
      result = described_class.build_rating_list
      rows = result[:action][:sections].first[:rows]

      expect(rows[0]).to eq({ id: "5", title: "⭐⭐⭐⭐⭐ Excelente" })
      expect(rows[1]).to eq({ id: "4", title: "⭐⭐⭐⭐ Muy bueno" })
      expect(rows[2]).to eq({ id: "3", title: "⭐⭐⭐ Bueno" })
      expect(rows[3]).to eq({ id: "2", title: "⭐⭐ Regular" })
      expect(rows[4]).to eq({ id: "1", title: "⭐ Malo" })
    end

    it "formats each rating with id and title" do
      result = described_class.build_rating_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row).to have_key(:id)
        expect(row).to have_key(:title)
        expect(row[:title]).to include("⭐")
      end
    end

    it "uses numeric string ids for ratings" do
      result = described_class.build_rating_list
      rows = result[:action][:sections].first[:rows]

      expect(rows.map { |r| r[:id] }).to eq(["5", "4", "3", "2", "1"])
    end

    it "respects 20-character title limit" do
      result = described_class.build_rating_list
      rows = result[:action][:sections].first[:rows]

      rows.each do |row|
        expect(row[:title].length).to be <= 20
      end
    end

    context "Meta Cloud API compliance" do
      it "returns payload matching Meta Cloud API List Message format" do
        result = described_class.build_rating_list

        # Verify top-level structure
        expect(result).to have_key(:type)
        expect(result).to have_key(:header)
        expect(result).to have_key(:body)
        expect(result).to have_key(:action)

        # Verify header structure
        expect(result[:header]).to have_key(:type)
        expect(result[:header]).to have_key(:text)

        # Verify body structure
        expect(result[:body]).to have_key(:text)

        # Verify action structure
        expect(result[:action]).to have_key(:button)
        expect(result[:action]).to have_key(:sections)

        # Verify sections structure
        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].first).to have_key(:title)
        expect(result[:action][:sections].first).to have_key(:rows)

        # Verify rows structure
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row).to have_key(:id)
          expect(row).to have_key(:title)
        end
      end

      it "respects 20-character button label limit" do
        result = described_class.build_rating_list

        expect(result[:action][:button].length).to be <= 20
      end

      it "respects 20-character row title limit" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end
    end

    context "requirement compliance" do
      it "matches Requirement 14 acceptance criteria" do
        result = described_class.build_rating_list

        # AC1: List Message with title "¿Cómo calificarías el trabajo?"
        expect(result[:header][:text]).to eq("¿Cómo calificarías el trabajo?")

        # AC2: Exactly five options with correct values
        rows = result[:action][:sections].first[:rows]
        expect(rows.length).to eq(5)
        expect(rows.map { |r| r[:title] }).to eq([
          "⭐⭐⭐⭐⭐ Excelente",
          "⭐⭐⭐⭐ Muy bueno",
          "⭐⭐⭐ Bueno",
          "⭐⭐ Regular",
          "⭐ Malo"
        ])
      end

      it "provides numeric string ids that can be stored in Review.rating field" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        # AC3: Numeric value (1-5) should be stored in Review rating field
        rows.each do |row|
          expect(row[:id]).to match(/^[1-5]$/)
          expect(row[:id].to_i).to be_between(1, 5)
        end
      end

      it "provides unique ids for each rating" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]
        ids = rows.map { |r| r[:id] }

        expect(ids.uniq.length).to eq(5)
        expect(ids).to eq(["5", "4", "3", "2", "1"])
      end
    end

    context "integration with review collection flow" do
      it "can be used in C7A star rating flow" do
        result = described_class.build_rating_list

        # Verify the payload is ready to be sent via WhatsApp service
        expect(result[:type]).to eq("list")
        expect(result[:action][:sections].first[:rows].length).to eq(5)

        # Verify all ids are suitable for database storage as integers
        rows = result[:action][:sections].first[:rows]
        rows.each do |row|
          expect(row[:id]).to be_a(String)
          expect(row[:id].to_i).to be_between(1, 5)
        end
      end

      it "provides ids that can be converted to numeric values for Review model" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        # All ids should be convertible to integers 1-5
        rows.each do |row|
          numeric_value = row[:id].to_i
          expect(numeric_value).to be_between(1, 5)
        end
      end

      it "orders ratings from best to worst (5 to 1)" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        # Ratings should be in descending order
        numeric_ratings = rows.map { |r| r[:id].to_i }
        expect(numeric_ratings).to eq([5, 4, 3, 2, 1])
      end
    end

    context "star emoji display" do
      it "displays correct number of stars for each rating" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        expect(rows[0][:title]).to start_with("⭐⭐⭐⭐⭐")  # 5 stars
        expect(rows[1][:title]).to start_with("⭐⭐⭐⭐")    # 4 stars
        expect(rows[2][:title]).to start_with("⭐⭐⭐")      # 3 stars
        expect(rows[3][:title]).to start_with("⭐⭐")        # 2 stars
        expect(rows[4][:title]).to start_with("⭐")          # 1 star
      end

      it "includes descriptive labels for each rating" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        expect(rows[0][:title]).to include("Excelente")
        expect(rows[1][:title]).to include("Muy bueno")
        expect(rows[2][:title]).to include("Bueno")
        expect(rows[3][:title]).to include("Regular")
        expect(rows[4][:title]).to include("Malo")
      end

      it "combines stars and labels in a readable format" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          # Each title should have stars followed by space and label
          expect(row[:title]).to match(/⭐+ \w+/)
        end
      end
    end

    context "title length validation" do
      it "all rating titles fit within 20 character limit" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title].length).to be <= 20
        end
      end

      it "does not truncate any rating titles" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        rows.each do |row|
          expect(row[:title]).not_to end_with("…")
        end
      end

      it "preserves full descriptive labels" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        # Verify complete labels are present
        expect(rows[0][:title]).to eq("⭐⭐⭐⭐⭐ Excelente")
        expect(rows[1][:title]).to eq("⭐⭐⭐⭐ Muy bueno")
        expect(rows[2][:title]).to eq("⭐⭐⭐ Bueno")
        expect(rows[3][:title]).to eq("⭐⭐ Regular")
        expect(rows[4][:title]).to eq("⭐ Malo")
      end
    end

    context "comparison with Quick Reply Buttons" do
      it "uses List Message format instead of Quick Reply Buttons" do
        result = described_class.build_rating_list

        # AC4: System SHALL NOT use Quick_Reply_Buttons for star rating selection
        expect(result[:type]).to eq("list")
        expect(result[:type]).not_to eq("button")
      end

      it "supports 5 options which exceeds Quick Reply Button limit of 3" do
        result = described_class.build_rating_list
        rows = result[:action][:sections].first[:rows]

        # Quick Reply Buttons are limited to 3 options
        # List Messages support 4+ options
        expect(rows.length).to eq(5)
        expect(rows.length).to be > 3
      end
    end
  end

  describe ".build_primary_trade_list" do
    let(:categories) { %w[Fontanero Electricista Albañil] }

    context "with multiple categories" do
      it "returns a valid List Message payload" do
        result = described_class.build_primary_trade_list(categories)

        expect(result).to be_a(Hash)
        expect(result[:type]).to eq("list")
      end

      it "includes header with title" do
        result = described_class.build_primary_trade_list(categories)

        expect(result[:header]).to eq({ type: "text", text: "Oficio principal" })
      end

      it "includes body text asking about frequency" do
        result = described_class.build_primary_trade_list(categories)

        expect(result[:body]).to eq({ text: "¿Cuál haces con más frecuencia?" })
      end

      it "includes action with button label" do
        result = described_class.build_primary_trade_list(categories)

        expect(result[:action][:button]).to eq("Ver opciones")
      end

      it "includes sections with categories" do
        result = described_class.build_primary_trade_list(categories)

        expect(result[:action][:sections]).to be_an(Array)
        expect(result[:action][:sections].length).to eq(1)
      end

      it "includes section with title" do
        result = described_class.build_primary_trade_list(categories)
        section = result[:action][:sections].first

        expect(section[:title]).to eq("Selecciona uno")
      end

      it "includes rows with all categories" do
        result = described_class.build_primary_trade_list(categories)
        rows = result[:action][:sections].first[:rows]

        expect(rows.length).to eq(4) # 3 categories + 1 "all equal" option
      end

      it "includes category rows with correct IDs" do
        result = described_class.build_primary_trade_list(categories)
        rows = result[:action][:sections].first[:rows]

        expect(rows[0][:id]).to eq("category_0")
        expect(rows[1][:id]).to eq("category_1")
        expect(rows[2][:id]).to eq("category_2")
      end

      it "includes category rows with correct titles" do
        result = described_class.build_primary_trade_list(categories)
        rows = result[:action][:sections].first[:rows]

        expect(rows[0][:title]).to eq("Fontanero")
        expect(rows[1][:title]).to eq("Electricista")
        expect(rows[2][:title]).to eq("Albañil")
      end

      it "includes 'all equal frequency' option as last row" do
        result = described_class.build_primary_trade_list(categories)
        rows = result[:action][:sections].first[:rows]

        expect(rows.last[:id]).to eq("all_equal")
        expect(rows.last[:title]).to eq("Todos igual frec.")
      end

      it "truncates 'all equal frequency' option to fit 20-char limit" do
        result = described_class.build_primary_trade_list(categories)
        rows = result[:action][:sections].first[:rows]

        # "Todos los hago con la misma frecuencia" is too long (42 chars)
        # Should be truncated to "Todos igual frec." (18 chars)
        expect(rows.last[:title].length).to be <= 20
      end
    end

    context "with long category names" do
      let(:long_categories) { ["Instalaciones hidráulicas", "Reparaciones eléctricas"] }

      it "truncates category names that exceed 20 characters" do
        result = described_class.build_primary_trade_list(long_categories)
        rows = result[:action][:sections].first[:rows]

        rows[0...-1].each do |row| # Exclude last "all equal" option
          expect(row[:title].length).to be <= 20
        end
      end

      it "adds ellipsis to truncated category names" do
        result = described_class.build_primary_trade_list(long_categories)
        rows = result[:action][:sections].first[:rows]

        # "Instalaciones hidráulicas" (26 chars) should be truncated
        expect(rows[0][:title]).to end_with("…")
      end
    end

    context "with two categories" do
      let(:two_categories) { %w[Fontanero Electricista] }

      it "includes 3 rows total (2 categories + 1 all equal option)" do
        result = described_class.build_primary_trade_list(two_categories)
        rows = result[:action][:sections].first[:rows]

        expect(rows.length).to eq(3)
      end
    end

    context "requirement validation" do
      it "includes 'Todos los hago con la misma frecuencia' option (AC1)" do
        result = described_class.build_primary_trade_list(categories)
        rows = result[:action][:sections].first[:rows]

        # Requirement 5 AC1: System SHALL include the option "Todos los hago con la misma frecuencia"
        all_equal_option = rows.find { |row| row[:id] == "all_equal" }
        expect(all_equal_option).to be_present
        expect(all_equal_option[:title]).to include("Todos")
      end

      it "uses List Message format for 4+ options" do
        result = described_class.build_primary_trade_list(categories)

        # With 3 categories + 1 "all equal" = 4 options
        # Quick Reply Buttons limited to 3, so List Message is required
        expect(result[:type]).to eq("list")
      end
    end
  end
end
