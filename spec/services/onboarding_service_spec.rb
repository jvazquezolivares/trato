# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingService do
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
    context "when stage is onboarding_welcome (first call after user chose '2')" do
      before do
        allow(redis_mock).to receive(:get)
          .with("onboarding_state:#{phone}")
          .and_return(redis_state(stage: "onboarding_welcome"))
        allow(redis_mock).to receive(:setex).and_return("OK")
      end

      it "transitions to collecting_name and asks for name" do
        described_class.call(from: phone, body: "2")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/cómo te llamas/i)
        )
      end

      it "saves collecting_name stage in Redis" do
        described_class.call(from: phone, body: "2")

        expect(redis_mock).to have_received(:setex).with(
          "onboarding_state:#{phone}",
          86_400,
          a_string_matching(/"stage":"collecting_name"/)
        )
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

      it "asks for city after categories" do
        described_class.call(from: phone, body: "fontanero")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: phone,
          message: a_string_matching(/ciudad/i)
        )
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
        assistant_whatsapp_link: "https://wa.me/522221234567?text=a3f8c2d1",
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
