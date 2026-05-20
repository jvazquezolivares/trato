# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingService do
  include ActiveSupport::Testing::TimeHelpers

  let(:phone) { "5212211234567" }
  let(:redis_mock) { instance_double(Redis) }

  before do
    stub_const("REDIS", redis_mock)
    allow(WhatsAppService).to receive(:send_message).and_return(true)
    allow(WhatsAppService).to receive(:send_multipart).and_return(true)
  end

  # Helper to build Redis state JSON
  def redis_state(stage:, data: {})
    { "stage" => stage, "data" => data }.to_json
  end

  describe ".call" do
    context "when stage is onboarding_welcome (first response after welcome message)" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "onboarding_welcome"))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "transitions to collecting_name and asks for name" do
        described_class.call(from: phone, body: "Hola")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/cómo te llamas/i)
        )
      end

      it "saves collecting_name stage in Redis" do
        described_class.call(from: phone, body: "Hola")

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"stage":"collecting_name"/)
        )
      end
    end

    context "when stage is onboarding_welcome and user declines registration" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "onboarding_welcome"))
        allow(redis_mock).to receive(:setex).and_return("OK")
        allow(WhatsAppService).to receive(:send_list_message).and_return(true)
      end

      it "sends decline reasons List Message when user says 'mejor después'" do
        described_class.call(from: phone, body: "Mejor después")

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: phone,
          payload: a_hash_including(
            type: "list",
            header: a_hash_including(text: "¿Por qué no por ahora?")
          )
        )
      end

      it "sends decline reasons List Message when user says 'no'" do
        described_class.call(from: phone, body: "no")

        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "sends decline reasons List Message when user says 'ahora no'" do
        described_class.call(from: phone, body: "ahora no")

        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "sends decline reasons List Message when user says 'más tarde'" do
        described_class.call(from: phone, body: "más tarde")

        expect(WhatsAppService).to have_received(:send_list_message)
      end

      it "transitions to collecting_decline_reason stage" do
        described_class.call(from: phone, body: "Mejor después")

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"stage":"collecting_decline_reason"/)
        )
      end
    end

    context "when collecting decline reason" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_decline_reason"))
        allow(redis_mock).to receive(:setex).and_return("OK")
        allow(redis_mock).to receive(:del).and_return(1)
      end

      after do
        travel_back
      end

      it "stores decline reason in database" do
        travel_to Time.current do
          expect do
            described_class.call(from: phone, body: "busy")
          end.to change(OnboardingDecline, :count).by(1)

          decline = OnboardingDecline.last
          expect(decline.phone).to eq(phone)
          expect(decline.reason).to eq("busy")
          expect(decline.context).to include(
            "stage" => "onboarding",
            "declined_at" => Time.current.iso8601
          )
        end
      end

      it "stores decline reason in Redis data" do
        described_class.call(from: phone, body: "dont_understand")

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"decline_reason":"dont_understand"/)
        ).at_least(:once)
      end

      it "sends warm closing message" do
        described_class.call(from: phone, body: "busy")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/Gracias por contarme.*Cuando quieras crear tu cuenta/m)
        )
      end

      it "sends warm closing message with correct emoji and tone" do
        described_class.call(from: phone, body: "busy")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/😊/)
        )
      end

      it "includes Elisa signature in closing message" do
        described_class.call(from: phone, body: "busy")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/— Elisa/)
        )
      end

      it "sets conversation stage to closed" do
        described_class.call(from: phone, body: "busy")

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"stage":"closed"/)
        )
      end

      it "prompts user to select from list when body is blank" do
        described_class.call(from: phone, body: "")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: "Por favor selecciona una razón de la lista."
        )
      end

      it "does not send closing message when body is blank" do
        described_class.call(from: phone, body: "")

        expect(WhatsAppService).not_to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/Gracias por contarme/)
        )
      end

      it "does not create OnboardingDecline record when body is blank" do
        expect do
          described_class.call(from: phone, body: "")
        end.not_to change(OnboardingDecline, :count)
      end

      it "stores all decline reason options correctly" do
        decline_reasons = %w[busy dont_understand not_worth_it uncomfortable_whatsapp enough_clients other]

        decline_reasons.each do |reason|
          expect do
            described_class.call(from: phone, body: reason)
          end.to change(OnboardingDecline, :count).by(1)

          decline = OnboardingDecline.last
          expect(decline.reason).to eq(reason)
        end
      end

      # Test each decline reason individually to ensure complete flow
      context "when testing each decline reason option" do
        DECLINE_REASONS = [
          { id: "busy", title: "Estoy muy ocupado" },
          { id: "dont_understand", title: "No entiendo qué es" },
          { id: "not_worth_it", title: "No sé si vale pena" },
          { id: "uncomfortable_whatsapp", title: "No me gusta WhatsApp" },
          { id: "enough_clients", title: "Tengo suficientes" },
          { id: "other", title: "Otro motivo" }
        ].freeze

        DECLINE_REASONS.each do |reason|
          context "when provider selects '#{reason[:title]}' (#{reason[:id]})" do
            it "stores the decline reason in database" do
              expect do
                described_class.call(from: phone, body: reason[:id])
              end.to change(OnboardingDecline, :count).by(1)

              decline = OnboardingDecline.last
              expect(decline.phone).to eq(phone)
              expect(decline.reason).to eq(reason[:id])
            end

            it "sends warm closing message with correct content" do
              described_class.call(from: phone, body: reason[:id])

              expect(WhatsAppService).to have_received(:send_message).with(
                to: phone,
                message: "¡Gracias por contarme! 😊 Cuando quieras crear tu cuenta, escríbeme aquí y con gusto te ayudo. ¡Que te vaya muy bien! — Elisa"
              )
            end

            it "sets conversation stage to closed" do
              described_class.call(from: phone, body: reason[:id])

              expect(redis_mock).to have_received(:setex).with(
                "onboarding_state:#{phone}",
                86_400,
                a_string_matching(/"stage":"closed"/)
              )
            end

            it "stores decline reason in Redis data before closing" do
              described_class.call(from: phone, body: reason[:id])

              expect(redis_mock).to have_received(:setex).with(
                "onboarding_state:#{phone}",
                86_400,
                a_string_matching(/"decline_reason":"#{reason[:id]}"/)
              ).at_least(:once)
            end
          end
        end
      end

      it "stores context with correct stage in database" do
        described_class.call(from: phone, body: "busy")

        decline = OnboardingDecline.last
        expect(decline.context["stage"]).to eq("onboarding")
      end

      it "stores timestamp in ISO8601 format" do
        travel_to Time.current do
          described_class.call(from: phone, body: "busy")

          decline = OnboardingDecline.last
          expect(decline.context["declined_at"]).to eq(Time.current.iso8601)
        end
      end

      it "maintains Redis state until closed stage is set" do
        described_class.call(from: phone, body: "busy")

        # Redis state should be updated to closed, not deleted yet
        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"stage":"closed"/)
        )
      end

      it "sends only one message when decline reason is selected" do
        described_class.call(from: phone, body: "busy")

        # Should send exactly one message (the closing message)
        expect(WhatsAppService).to have_received(:send_message).once
      end
    end

    context "when collecting name" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_name"))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores name and asks for categories" do
        described_class.call(from: phone, body: "Miguel García")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/qué te dedicas/i)
        )
      end

      it "stores the name in Redis data" do
        described_class.call(from: phone, body: "Miguel García")

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"name":"Miguel García"/)
        )
      end

      it "repeats question when body is blank" do
        described_class.call(from: phone, body: "")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/nombre/i)
        )
      end
    end

    context "when collecting categories" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_categories", data: { "name" => "Miguel" }))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "parses multiple categories separated by commas" do
        described_class.call(from: phone, body: "fontanero, electricista, albañil")

        expect(redis_mock).to have_received(:setex) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["categories"]).to eq(%w[fontanero electricista albañil])
        end
      end

      it "parses categories separated by 'y'" do
        described_class.call(from: phone, body: "fontanero y electricista")

        expect(redis_mock).to have_received(:setex) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["categories"]).to eq(%w[fontanero electricista])
        end
      end

      it "cleans common prefixes from categories" do
        described_class.call(from: phone, body: "Soy fontanero, me dedico a electricista")

        expect(redis_mock).to have_received(:setex) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["categories"]).to eq(%w[fontanero electricista])
        end
      end

      it "asks for city after categories" do
        described_class.call(from: phone, body: "fontanero")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/ciudad/i)
        )
      end

      context "when provider has multiple categories" do
        before do
          allow(WhatsAppService).to receive(:send_list_message).and_return(true)
        end

        it "sends primary trade selection List Message" do
          described_class.call(from: phone, body: "fontanero, electricista, albañil")

          expect(WhatsAppService).to have_received(:send_list_message).with(
            to: phone,
            payload: a_hash_including(
              type: "list",
              header: a_hash_including(text: "Oficio principal")
            )
          )
        end

        it "transitions to collecting_primary_trade stage" do
          described_class.call(from: phone, body: "fontanero, electricista")

          expect(redis_mock).to have_received(:setex).with(
            "onboarding_state:#{phone}",
            86_400,
            a_string_matching(/"stage":"collecting_primary_trade"/)
          )
        end

        it "includes all categories in the List Message" do
          described_class.call(from: phone, body: "fontanero, electricista, albañil")

          expect(WhatsAppService).to have_received(:send_list_message) do |args|
            payload = args[:payload]
            rows = payload[:action][:sections][0][:rows]

            # Should have 3 categories + 1 "all equal" option = 4 rows
            expect(rows.length).to eq(4)
            expect(rows.last[:id]).to eq("all_equal")
          end
        end
      end

      context "when provider has single category" do
        it "skips primary trade selection and goes directly to city" do
          described_class.call(from: phone, body: "fontanero")

          expect(WhatsAppService).to have_received(:send_message).with(
            to: phone,
            message: a_string_matching(/ciudad/i)
          )
        end

        it "does not send primary trade List Message" do
          allow(WhatsAppService).to receive(:send_list_message)

          described_class.call(from: phone, body: "fontanero")

          expect(WhatsAppService).not_to have_received(:send_list_message)
        end
      end
    end

    context "when collecting primary trade" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(
            stage: "collecting_primary_trade",
            data: {
              "name" => "Miguel",
              "categories" => %w[fontanero electricista albañil]
            }
          ))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores primary_trade_index when specific category selected" do
        described_class.call(from: phone, body: "electricista")

        expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["primary_trade_index"]).to eq(1) if parsed["data"]["primary_trade_index"]
        end
      end

      it "stores primary_trade_index as 0 when 'all equal' selected" do
        described_class.call(from: phone, body: "Todos con igual frecuencia")

        expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["primary_trade_index"]).to eq(0) if parsed["data"]["primary_trade_index"]
        end
      end

      it "handles 'todos' keyword for all equal option" do
        described_class.call(from: phone, body: "todos")

        expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["primary_trade_index"]).to eq(0) if parsed["data"]["primary_trade_index"]
        end
      end

      it "handles 'igual' keyword for all equal option" do
        described_class.call(from: phone, body: "igual frecuencia")

        expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["primary_trade_index"]).to eq(0) if parsed["data"]["primary_trade_index"]
        end
      end

      it "handles 'all_equal' list message ID for all equal option" do
        described_class.call(from: phone, body: "all_equal")

        expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["primary_trade_index"]).to eq(0) if parsed["data"]["primary_trade_index"]
        end
      end

      it "sets first category as primary when all equal option selected" do
        described_class.call(from: phone, body: "all_equal")

        expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          # First category (fontanero at index 0) should be primary
          expect(parsed["data"]["primary_trade_index"]).to eq(0) if parsed["data"]["primary_trade_index"]
        end
      end

      it "asks for city after primary trade selection" do
        described_class.call(from: phone, body: "electricista")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/ciudad/i)
        )
      end

      it "handles category_X format from List Message ID" do
        described_class.call(from: phone, body: "category_2")

        expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["primary_trade_index"]).to eq(2) if parsed["data"]["primary_trade_index"]
        end
      end

      it "prompts to select from list when category not recognized" do
        described_class.call(from: phone, body: "carpintero")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/no entendí.*lista/i)
        )
      end

      context "when testing equal frequency selection flow" do
        it "correctly flows from 'all equal' selection to city collection" do
          described_class.call(from: phone, body: "all_equal")

          # Verify primary_trade_index is set to 0
          expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
            parsed = JSON.parse(json)
            expect(parsed["data"]["primary_trade_index"]).to eq(0) if parsed["data"]["primary_trade_index"]
          end

          # Verify stage transitions to collecting_city
          expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
            parsed = JSON.parse(json)
            expect(parsed["stage"]).to eq("collecting_city") if parsed["stage"] == "collecting_city"
          end

          # Verify city question is asked
          expect(WhatsAppService).to have_received(:send_message).with(
            to: phone,
            message: a_string_matching(/ciudad/i)
          )
        end

        it "handles various 'all equal' keyword variations" do
          variations = [
            "all_equal",
            "todos",
            "Todos con igual frecuencia",
            "igual frecuencia",
            "todos igual",
            "TODOS"
          ]

          variations.each do |variation|
            # Reset mocks for each iteration
            allow(redis_mock).to receive(:setex).and_return("OK")
            allow(WhatsAppService).to receive(:send_message).and_return(true)

            described_class.call(from: phone, body: variation)

            # Verify primary_trade_index is set to 0 for each variation
            expect(redis_mock).to have_received(:setex).at_least(:once) do |_key, _ttl, json|
              parsed = JSON.parse(json)
              expect(parsed["data"]["primary_trade_index"]).to eq(0) if parsed["data"]["primary_trade_index"]
            end
          end
        end
      end
    end

    context "when collecting city" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_city", data: { "name" => "Miguel", "categories" => [ "fontanero" ] }))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores city and asks for service area" do
        described_class.call(from: phone, body: "Veracruz")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/zonas.*Veracruz/i)
        )
      end
    end

    context "when collecting area" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_area", data: {
            "name" => "Miguel", "categories" => [ "fontanero" ], "city" => "Veracruz"
          }))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores area and asks for price" do
        described_class.call(from: phone, body: "Boca del Río, Centro")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/diagnóstico/i)
        )
      end
    end

    context "when collecting price" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_price", data: {
            "name" => "Miguel", "categories" => [ "fontanero" ], "city" => "Veracruz",
            "service_area" => "Boca del Río"
          }))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "extracts numeric price and asks for experience" do
        described_class.call(from: phone, body: "$300 pesos")

        expect(redis_mock).to have_received(:setex) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["base_price"]).to eq("300")
        end

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/experiencia/i)
        )
      end
    end

    context "when collecting experience" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_experience", data: {
            "name" => "Miguel", "categories" => [ "fontanero" ], "city" => "Veracruz",
            "service_area" => "Boca del Río", "base_price" => "300"
          }))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores experience and asks for specialties" do
        described_class.call(from: phone, body: "8 años")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/especiali/i)
        )
      end
    end

    context "when collecting specialties" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_specialties", data: {
            "name" => "Miguel", "categories" => [ "fontanero" ], "city" => "Veracruz",
            "service_area" => "Boca del Río", "base_price" => "300", "years_experience" => "8"
          }))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores specialties and asks for specialized work" do
        described_class.call(from: phone, body: "urgencias e instalaciones")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/especializado/i)
        )
      end
    end

    context "when collecting specialized work" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_specialized_work", data: {
            "name" => "Miguel", "categories" => [ "fontanero" ], "city" => "Veracruz",
            "service_area" => "Boca del Río", "base_price" => "300",
            "years_experience" => "8", "specialties" => "urgencias"
          }))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores specialized work and asks first bio question" do
        described_class.call(from: phone, body: "calentadores solares")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/qué es lo que más te gusta/i)
        )
      end
    end
  end

  describe "bio generation flow" do
    let(:full_data) do
      {
        "name" => "Miguel García", "categories" => [ "fontanero" ],
        "city" => "Veracruz", "service_area" => "Boca del Río",
        "base_price" => "300", "years_experience" => "8",
        "specialties" => "urgencias", "specialized_work" => "calentadores",
        "bio_answers" => [ "Me gusta ayudar", "Un panel completo", "Soy puntual" ],
        "bio_question_index" => 3
      }
    end

    context "when answering bio questions" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "bio_questions", data: full_data.merge("bio_question_index" => 2)))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "asks the next bio question after receiving an answer" do
        described_class.call(from: phone, body: "Soy puntual y limpio")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/clientes sepan/i)
        )
      end
    end

    context "when all bio questions answered" do
      let(:claude_response) do
        {
          "message" => "Miguel es un fontanero con 8 años de experiencia en Veracruz...",
          "action" => "none",
          "should_save_message" => false
        }
      end

      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "bio_questions", data: full_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
        allow(ClaudeService).to receive(:call).and_return(claude_response)
      end

      it "generates bio with Claude Sonnet and presents for approval" do
        described_class.call(from: phone, body: "Que soy honesto")

        expect(ClaudeService).to have_received(:call).with(
          model: :sonnet,
          system_prompt: a_string_matching(/biografía/i),
          user_message: a_string_matching(/Miguel/),
          context: {}
        )

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/te gusta.*descripción/i)
        )
      end
    end

    context "when reviewing bio — approval" do
      let(:bio_data) { full_data.merge("generated_bio" => "Miguel es fontanero...", "bio_revision_count" => 0) }

      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "bio_review", data: bio_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "accepts bio and moves to profile photo when user says sí" do
        described_class.call(from: phone, body: "sí")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/foto.*perfil/i)
        )
      end
    end

    context "when reviewing bio — first revision request" do
      let(:bio_data) { full_data.merge("generated_bio" => "Miguel es fontanero...", "bio_revision_count" => 0) }
      let(:claude_response) do
        { "message" => "Miguel, fontanero experimentado...", "action" => "none", "should_save_message" => false }
      end

      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "bio_review", data: bio_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
        allow(ClaudeService).to receive(:call).and_return(claude_response)
      end

      it "regenerates bio with feedback" do
        described_class.call(from: phone, body: "Hazla más corta")

        expect(ClaudeService).to have_received(:call).with(
          model: :sonnet,
          system_prompt: a_string_matching(/biografía/i),
          user_message: a_string_matching(/cambios/i),
          context: {}
        )
      end
    end

    context "when reviewing bio — after 2 failed revisions" do
      let(:bio_data) { full_data.merge("generated_bio" => "Miguel es fontanero...", "bio_revision_count" => 1) }

      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "bio_review", data: bio_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "asks provider to dictate bio directly after 2 revisions" do
        described_class.call(from: phone, body: "No me gusta")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/propias palabras/i)
        )
      end
    end

    context "when provider dictates bio directly" do
      let(:bio_data) do
        full_data.merge(
          "generated_bio" => "Miguel es fontanero...",
          "bio_revision_count" => 2,
          "awaiting_dictated_bio" => true
        )
      end

      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "bio_review", data: bio_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "uses dictated text as bio and moves to profile photo" do
        described_class.call(from: phone, body: "Soy Miguel, fontanero con 8 años de experiencia")

        expect(redis_mock).to have_received(:setex) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["bio"]).to eq("Soy Miguel, fontanero con 8 años de experiencia")
        end

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/foto.*perfil/i)
        )
      end
    end
  end

  describe "photo collection" do
    let(:base_data) do
      {
        "name" => "Miguel", "categories" => [ "fontanero" ], "city" => "Veracruz",
        "service_area" => "Boca del Río", "base_price" => "300",
        "bio" => "Miguel es fontanero..."
      }
    end

    context "when collecting profile photo — user declines" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_profile_photo", data: base_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "skips to work photos" do
        described_class.call(from: phone, body: "no")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/fotos.*trabajos/i)
        )
      end
    end

    context "when collecting work photos — user says listo" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_work_photos", data: base_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "moves to Facebook explanation" do
        described_class.call(from: phone, body: "listo")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/Facebook/i)
        )
      end
    end

    context "when collecting work photos — user sends more" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_work_photos", data: base_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "acknowledges and asks for more" do
        described_class.call(from: phone, body: "foto de trabajo")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/guardada/i)
        )
      end
    end
  end

  describe "Facebook and email collection" do
    let(:base_data) do
      {
        "name" => "Miguel", "categories" => [ "fontanero" ], "city" => "Veracruz",
        "service_area" => "Boca del Río", "base_price" => "300",
        "bio" => "Miguel es fontanero..."
      }
    end

    context "when explaining Facebook — user provides URL" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "explaining_facebook", data: base_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "stores URL and asks for email" do
        described_class.call(from: phone, body: "https://facebook.com/miguelelectricista")

        expect(redis_mock).to have_received(:setex) do |_key, _ttl, json|
          parsed = JSON.parse(json)
          expect(parsed["data"]["facebook_page_url"]).to eq("https://facebook.com/miguelelectricista")
        end

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/correo/i)
        )
      end
    end

    context "when explaining Facebook — user declines" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "explaining_facebook", data: base_data))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "skips Facebook and asks for email" do
        described_class.call(from: phone, body: "no")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/correo/i)
        )
      end
    end
  end

  describe "provider creation and completion" do
    let(:complete_data) do
      {
        "name" => "Miguel García", "categories" => [ "fontanero", "electricista" ],
        "city" => "Veracruz", "service_area" => "Boca del Río, Centro",
        "base_price" => "300", "bio" => "Miguel es fontanero con experiencia...",
        "email" => "miguel@gmail.com", "facebook_page_url" => nil
      }
    end

    let(:provider_double) do
      instance_double(
        Provider,
        name: "Miguel García",
        short_uuid: "a3f8c2d1",
        slug: "fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1",
        assistant_whatsapp_link: a_string_matching(/Env.*Miguel.*a3f8c2d1/),
        provider_categories: provider_categories_relation,
        "slug=" => nil,
        save!: true,
        build_slug: "fontaneros-en-veracruz/miguel-garcia-fontanero-a3f8c2d1"
      )
    end

    let(:provider_categories_relation) { double("categories_relation") }

    before do
      allow(redis_mock).to receive(:get)
        .with("onboarding_state:#{phone}")
        .and_return(redis_state(stage: "collecting_email", data: complete_data))
      allow(redis_mock).to receive(:setex).and_return("OK")
      allow(redis_mock).to receive(:del).and_return(1)
      allow(Provider).to receive(:new).and_return(provider_double)
      allow(provider_categories_relation).to receive(:build)
      allow(SecureRandom).to receive(:hex).with(4).and_return("a3f8c2d1")
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("TRATO_WHATSAPP_NUMBER").and_return("522221234567")
    end

    context "when user provides email" do
      it "creates provider with correct attributes" do
        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(Provider).to have_received(:new).with(hash_including(
          name: "Miguel García",
          phone: phone,
          city: "Veracruz",
          bio: "Miguel es fontanero con experiencia...",
          email: "miguel@gmail.com",
          active: true
        ))
      end

      it "creates categories with first as primary" do
        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(provider_categories_relation).to have_received(:build).with(
          hash_including(name: "Fontanero", slug: "fontanero", primary: true)
        )
        expect(provider_categories_relation).to have_received(:build).with(
          hash_including(name: "Electricista", slug: "electricista", primary: false)
        )
      end

      it "creates categories with selected primary when primary_trade_index is set" do
        # Update complete_data to include primary_trade_index
        data_with_primary = complete_data.merge("primary_trade_index" => 1)

        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_email", data: data_with_primary))

        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(provider_categories_relation).to have_received(:build).with(
          hash_including(name: "Fontanero", slug: "fontanero", primary: false)
        )
        expect(provider_categories_relation).to have_received(:build).with(
          hash_including(name: "Electricista", slug: "electricista", primary: true)
        )
      end

      it "creates categories with first as primary when 'all equal' selected (primary_trade_index = 0)" do
        # Update complete_data to include primary_trade_index = 0 (all equal frequency)
        data_with_all_equal = complete_data.merge("primary_trade_index" => 0)

        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "collecting_email", data: data_with_all_equal))

        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(provider_categories_relation).to have_received(:build).with(
          hash_including(name: "Fontanero", slug: "fontanero", primary: true)
        )
        expect(provider_categories_relation).to have_received(:build).with(
          hash_including(name: "Electricista", slug: "electricista", primary: false)
        )
      end

      it "builds and assigns slug" do
        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(provider_double).to have_received(:build_slug)
        expect(provider_double).to have_received(:save!)
      end

      it "cleans up Redis state" do
        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(redis_mock).to have_received(:del).with("onboarding_state:#{phone}")
      end

      it "sends confirmation with profile link and assistant link" do
        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/perfil.*activo/i)
        )
      end

      it "sends capabilities as multipart messages" do
        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(WhatsAppService).to have_received(:send_multipart).with(
          to: phone,
          messages: an_instance_of(Array)
        )
      end

      it "sends auto-reply suggestion" do
        described_class.call(from: phone, body: "miguel@gmail.com")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/respuesta automática/i)
        )
      end
    end

    context "when user declines email" do
      it "creates provider without email" do
        described_class.call(from: phone, body: "no")

        expect(Provider).to have_received(:new).with(hash_including(email: nil))
      end
    end
  end

  describe "helper methods" do
    let(:service) { described_class.new(from: phone, body: "") }

    before do
      allow(redis_mock).to receive(:get).and_return(nil)
    end

    describe "#parse_categories (via reflection)" do
      it "splits by comma" do
        result = service.send(:parse_categories, "fontanero, electricista")
        expect(result).to eq(%w[fontanero electricista])
      end

      it "splits by 'y'" do
        result = service.send(:parse_categories, "fontanero y electricista")
        expect(result).to eq(%w[fontanero electricista])
      end

      it "handles mixed separators" do
        result = service.send(:parse_categories, "fontanero, electricista y albañil")
        expect(result).to eq(%w[fontanero electricista albañil])
      end
    end

    describe "#extract_price" do
      it "extracts numeric value from peso format" do
        expect(service.send(:extract_price, "$300 pesos")).to eq("300")
      end

      it "extracts plain number" do
        expect(service.send(:extract_price, "300")).to eq("300")
      end

      it "handles decimal prices" do
        expect(service.send(:extract_price, "$350.50")).to eq("350.50")
      end
    end

    describe "#affirmative_response?" do
      %w[sí si yes ok vale perfecto].each do |word|
        it "recognizes '#{word}' as affirmative" do
          expect(service.send(:affirmative_response?, word)).to be true
        end
      end

      it "returns false for negative responses" do
        expect(service.send(:affirmative_response?, "no")).to be false
      end
    end

    describe "#negative_response?" do
      %w[no nop nel nah].each do |word|
        it "recognizes '#{word}' as negative" do
          expect(service.send(:negative_response?, word)).to be true
        end
      end

      it "returns false for affirmative responses" do
        expect(service.send(:negative_response?, "sí")).to be false
      end
    end
  end
end
