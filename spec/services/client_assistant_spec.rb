# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientAssistant do
  let(:provider) do
    instance_double(
      Provider,
      id: 1,
      name: "Miguel García",
      phone: "5212211234567",
      city: "Veracruz",
      short_uuid: "a3f8c2d1",
      service_area: "Boca del Río, Centro",
      base_price: 300,
      bio: "Electricista con 8 años de experiencia",
      slug: "electricistas-en-veracruz/miguel-garcia-electricista-a3f8c2d1",
      assistant_whatsapp_link: "https://wa.me/522221234567?text=a3f8c2d1"
    )
  end

  let(:client) { instance_double(Client, id: 42, name: "Mariana López", phone: client_phone, new_record?: false) }
  let(:client_phone) { "5212219876543" }

  let(:conversation) do
    instance_double(
      Conversation,
      id: 1,
      context: {},
      messages: messages_relation,
      provider: provider,
      client: client,
      "client=" => nil,
      "stage=" => nil,
      "context=" => nil,
      "last_message_at=" => nil
    )
  end

  let(:messages_relation) { double("messages_relation") }
  let(:ordered_messages) { double("ordered_messages") }
  let(:limited_messages) { [] }

  let(:claude_response) do
    {
      "message" => "Hola, soy Elisa, la asistente de Miguel García. ¿En qué te puedo ayudar?",
      "action" => "none",
      "action_data" => {},
      "new_stage" => "active",
      "updated_context" => {},
      "should_save_message" => true,
      "intent" => "client_first_contact"
    }
  end

  let(:provider_categories_relation) { double("categories_relation") }
  let(:reviews_relation) { double("reviews_relation") }
  let(:work_days_relation) { double("work_days_relation") }
  let(:photos_relation) { double("photos_relation") }

  before do
    # Client lookup
    allow(Client).to receive(:find_or_initialize_by).with(phone: client_phone).and_return(client)
    allow(client).to receive(:save!).and_return(true)

    # Conversation management
    allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
    allow(conversation).to receive(:update!).and_return(true)

    # Messages chain
    allow(messages_relation).to receive(:order).and_return(ordered_messages)
    allow(ordered_messages).to receive(:limit).and_return(limited_messages)
    allow(messages_relation).to receive(:create!).and_return(true)

    # Provider associations
    allow(provider).to receive(:provider_categories).and_return(provider_categories_relation)
    allow(provider_categories_relation).to receive(:pluck).with(:name).and_return(["Electricista"])
    allow(provider_categories_relation).to receive(:pluck).with(:slug).and_return(["electricista"])

    # Reviews
    allow(provider).to receive(:reviews).and_return(reviews_relation)
    allow(reviews_relation).to receive(:where).with(verified: true).and_return(reviews_relation)
    allow(reviews_relation).to receive(:count).and_return(5)
    allow(reviews_relation).to receive(:average).with(:rating).and_return(4.5)
    allow(reviews_relation).to receive(:empty?).and_return(false)
    allow(reviews_relation).to receive(:order).and_return(reviews_relation)
    allow(reviews_relation).to receive(:limit).and_return([])

    # Work days
    allow(provider).to receive(:work_days).and_return(work_days_relation)
    allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(nil)

    # Photos
    allow(provider).to receive(:photos).and_return(photos_relation)
    allow(photos_relation).to receive(:where).with(profile_photo: false).and_return(photos_relation)
    allow(photos_relation).to receive(:pluck).with(:category_tags).and_return([["electricista"], ["fontanero"]])
    allow(photos_relation).to receive(:where).with("category_tags @> ?", anything).and_return(photos_relation)
    allow(photos_relation).to receive(:limit).and_return([])

    # External services
    allow(ClaudeService).to receive(:call).and_return(claude_response)
    allow(WhatsAppService).to receive(:send_message).and_return(true)
    allow(WhatsAppService).to receive(:send_multipart).and_return(true)
  end

  describe ".call" do
    it "finds or initializes a client by phone" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(Client).to have_received(:find_or_initialize_by).with(phone: client_phone)
    end

    it "finds or creates a conversation scoped to provider and phone" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(Conversation).to have_received(:find_or_create_by!).with(
        provider: provider,
        phone: client_phone,
        role: "client"
      )
    end

    it "calls ClaudeService with haiku model" do
      described_class.call(provider: provider, from: client_phone, body: "Necesito un electricista")

      expect(ClaudeService).to have_received(:call).with(
        model: :haiku,
        system_prompt: a_string_matching(/Elisa.*asistente de Miguel García/),
        user_message: "Necesito un electricista",
        context: hash_including("history")
      )
    end

    it "sends reply via WhatsAppService" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(WhatsAppService).to have_received(:send_message).with(
        to: client_phone,
        message: claude_response["message"]
      )
    end

    it "updates conversation with last_message_at" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(conversation).to have_received(:update!).with(
        hash_including(:last_message_at)
      )
    end

    it "returns the Claude response" do
      result = described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(result).to eq(claude_response)
    end
  end

  describe "system prompt" do
    it "includes provider name" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Miguel García/))
      )
    end

    it "includes provider categories" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Electricista/))
      )
    end

    it "includes provider city" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Veracruz/))
      )
    end

    it "includes base price" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/300/))
      )
    end

    it "includes review stats" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/4\.5\/5.*5 reseñas/))
      )
    end

    it "includes provider phone for escalation" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/5212211234567/))
      )
    end
  end

  describe "message persistence" do
    context "when should_save_message is false" do
      let(:claude_response) do
        {
          "message" => "De nada 😊",
          "action" => "none",
          "action_data" => {},
          "new_stage" => nil,
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      it "does not persist the message" do
        described_class.call(provider: provider, from: client_phone, body: "gracias")

        expect(messages_relation).not_to have_received(:create!)
      end
    end

    context "when should_save_message is true" do
      let(:claude_response) do
        {
          "message" => "Hola, soy Elisa, la asistente de Miguel. ¿En qué te puedo ayudar?",
          "action" => "none",
          "action_data" => {},
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "client_first_contact"
        }
      end

      it "persists the inbound message" do
        described_class.call(provider: provider, from: client_phone, body: "a3f8c2d1")

        expect(messages_relation).to have_received(:create!).with(
          hash_including(
            direction: "inbound",
            body: "a3f8c2d1",
            intent: "client_first_contact",
            processed: true
          )
        )
      end

      it "persists the outbound reply" do
        described_class.call(provider: provider, from: client_phone, body: "a3f8c2d1")

        expect(messages_relation).to have_received(:create!).with(
          hash_including(
            direction: "outbound",
            body: claude_response["message"],
            intent: "client_first_contact",
            processed: true
          )
        )
      end
    end
  end

  describe "conversation stage update" do
    context "when Claude returns a new_stage" do
      let(:claude_response) do
        {
          "message" => "¿Qué servicio necesitas?",
          "action" => "none",
          "action_data" => {},
          "new_stage" => "collecting_info",
          "updated_context" => { "step" => "service_type" },
          "should_save_message" => false,
          "intent" => nil
        }
      end

      it "updates conversation stage" do
        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(conversation).to have_received(:update!).with(
          hash_including(stage: "collecting_info")
        )
      end

      it "updates conversation context" do
        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(conversation).to have_received(:update!).with(
          hash_including(context: { "step" => "service_type" })
        )
      end
    end
  end

  describe "action execution" do
    context "when action is create_appointment" do
      let(:claude_response) do
        {
          "message" => "Listo, agendé tu cita con Miguel para mañana a las 10am 📅",
          "action" => "create_appointment",
          "action_data" => {
            "description" => "Revisión eléctrica en cocina",
            "address" => "Calle Independencia 45, Boca del Río",
            "date" => Date.tomorrow.to_s,
            "time" => "10:00",
            "duration" => "90"
          },
          "new_stage" => "awaiting_provider",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "appointment_confirmed"
        }
      end

      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          description: "Revisión eléctrica en cocina",
          address: "Calle Independencia 45, Boca del Río",
          scheduled_at: Time.zone.parse("#{Date.tomorrow} 10:00"),
          estimated_duration: 90
        )
      end

      before do
        allow(Appointment).to receive(:create!).and_return(appointment)
        allow(work_days_relation).to receive(:find_by).with(date: Date.tomorrow).and_return(nil)
      end

      it "creates an appointment" do
        described_class.call(provider: provider, from: client_phone, body: "Sí, mañana a las 10 está bien")

        expect(Appointment).to have_received(:create!).with(
          hash_including(
            provider: provider,
            client: client,
            description: "Revisión eléctrica en cocina",
            address: "Calle Independencia 45, Boca del Río",
            status: "pending",
            how_client_arrived: "whatsapp_direct"
          )
        )
      end

      it "notifies the provider with appointment summary" do
        described_class.call(provider: provider, from: client_phone, body: "Sí, mañana a las 10 está bien")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Nueva cita agendada/)
        )
      end

      it "includes client name in provider notification" do
        described_class.call(provider: provider, from: client_phone, body: "Sí, mañana a las 10 está bien")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Mariana López/)
        )
      end

      it "includes client phone in provider notification" do
        described_class.call(provider: provider, from: client_phone, body: "Sí, mañana a las 10 está bien")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/5212219876543/)
        )
      end
    end

    context "when action is send_photos" do
      let(:claude_response) do
        {
          "message" => "Te muestro algunas fotos de trabajos similares 📸",
          "action" => "send_photos",
          "action_data" => { "category" => "electricista" },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      let(:photo) do
        instance_double(
          Photo,
          url: "https://trato-photos.s3.amazonaws.com/photos/panel.jpg",
          caption: "Panel eléctrico residencial"
        )
      end

      before do
        allow(photos_relation).to receive(:limit).with(5).and_return([photo])
      end

      it "sends work photos via multipart" do
        described_class.call(provider: provider, from: client_phone, body: "Quiero ver fotos")

        expect(WhatsAppService).to have_received(:send_multipart).with(
          to: client_phone,
          messages: array_including(a_string_matching(/Panel eléctrico/))
        )
      end

      it "sends profile link after photos" do
        described_class.call(provider: provider, from: client_phone, body: "Quiero ver fotos")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(%r{trato\.mx/p/})
        )
      end
    end

    context "when action is send_review_summary" do
      let(:claude_response) do
        {
          "message" => "Miguel tiene muy buenas reseñas, te las muestro:",
          "action" => "send_review_summary",
          "action_data" => {},
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      it "sends review summary to client" do
        described_class.call(provider: provider, from: client_phone, body: "¿Tiene buenas reseñas?")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/4\.5\/5.*5 reseñas verificadas/)
        )
      end

      it "sends profile link after review summary" do
        described_class.call(provider: provider, from: client_phone, body: "¿Tiene buenas reseñas?")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/Perfil completo/)
        )
      end
    end

    context "when action is send_provider_phone" do
      let(:claude_response) do
        {
          "message" => "Claro, te paso su número.",
          "action" => "send_provider_phone",
          "action_data" => {},
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "provider_unavailable"
        }
      end

      it "sends provider phone number to client" do
        described_class.call(provider: provider, from: client_phone, body: "Quiero hablar con él directamente")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/5212211234567/)
        )
      end
    end

    context "when action is escalate" do
      let(:claude_response) do
        {
          "message" => "Entiendo tu frustración. Voy a contactar a Miguel directamente para que te ayude.",
          "action" => "escalate",
          "action_data" => { "reason" => "complaint", "detail" => "Queja sobre trabajo previo" },
          "new_stage" => "escalated",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "complaint_received"
        }
      end

      it "sets conversation stage to escalated" do
        described_class.call(provider: provider, from: client_phone, body: "El trabajo quedó mal")

        expect(conversation).to have_received(:update!).with(
          hash_including(stage: "escalated")
        ).at_least(:once)
      end

      it "notifies provider via WhatsApp with context" do
        described_class.call(provider: provider, from: client_phone, body: "El trabajo quedó mal")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/Queja de cliente/)
        ).at_least(:once)
      end

      it "includes client phone in escalation message" do
        described_class.call(provider: provider, from: client_phone, body: "El trabajo quedó mal")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/5212219876543/)
        ).at_least(:once)
      end
    end

    context "when action is none" do
      it "does not create appointments" do
        allow(Appointment).to receive(:create!)

        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(Appointment).not_to have_received(:create!)
      end
    end
  end

  describe "escalation triggers" do
    context "when single-word danger keywords are detected" do
      # Representative sample across trade categories
      %w[humo quemado chispas cortocircuito incendio fuego llamas
         derrumbe emergencia peligro auxilio ambulancia bomberos accidente].each do |keyword|
        it "escalates when message contains '#{keyword}'" do
          described_class.call(provider: provider, from: client_phone, body: "Hay #{keyword} en mi casa")

          expect(conversation).to have_received(:update!).with(
            hash_including(stage: "escalated")
          ).at_least(:once)
        end

        it "notifies provider about danger for '#{keyword}'" do
          described_class.call(provider: provider, from: client_phone, body: "Hay #{keyword} en mi casa")

          expect(WhatsAppService).to have_received(:send_message).with(
            to: provider.phone,
            message: a_string_matching(/URGENTE.*emergencia/m)
          )
        end
      end
    end

    context "when multi-word danger phrases are detected" do
      [
        "fuga de gas", "olor a quemado", "fuga de agua",
        "agua por todos lados", "no puedo respirar", "ayuda urgente",
        "fuga de refrigerante", "se calentó mucho", "sacó chispas"
      ].each do |phrase|
        it "escalates when message contains '#{phrase}'" do
          described_class.call(provider: provider, from: client_phone, body: "Oye, hay #{phrase}")

          expect(conversation).to have_received(:update!).with(
            hash_including(stage: "escalated")
          ).at_least(:once)
        end
      end
    end

    context "when short keywords appear inside unrelated words" do
      it "does not escalate for 'gastos' (contains 'gas')" do
        described_class.call(provider: provider, from: client_phone, body: "Tengo muchos gastos este mes")

        expect(WhatsAppService).not_to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/URGENTE/)
        )
      end
    end

    context "when no danger keywords are present" do
      it "does not escalate for normal messages" do
        described_class.call(provider: provider, from: client_phone, body: "Necesito revisar mi instalación")

        expect(WhatsAppService).not_to have_received(:send_message).with(
          to: provider.phone,
          message: a_string_matching(/URGENTE/)
        )
      end
    end
  end

  describe "availability check" do
    context "when provider has a work day today" do
      let(:work_day) do
        instance_double(
          WorkDay,
          status: "active",
          starts_at: Time.zone.parse("08:00"),
          ends_at: Time.zone.parse("18:00")
        )
      end

      before do
        allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(work_day)
      end

      it "includes availability in system prompt" do
        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(ClaudeService).to have_received(:call).with(
          hash_including(system_prompt: a_string_matching(/Disponible hoy de 08:00 a 18:00/))
        )
      end
    end

    context "when provider has no work day today" do
      it "indicates no availability reported" do
        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(ClaudeService).to have_received(:call).with(
          hash_including(system_prompt: a_string_matching(/No ha reportado disponibilidad hoy/))
        )
      end
    end
  end

  describe "conversation context" do
    let(:message_double) do
      instance_double(Message, direction: "inbound", body: "Necesito un electricista", created_at: 1.hour.ago)
    end

    let(:limited_messages) { [message_double] }

    it "builds history from recent messages" do
      described_class.call(provider: provider, from: client_phone, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(
          context: hash_including(
            "history" => [{ "role" => "user", "content" => "Necesito un electricista" }]
          )
        )
      )
    end
  end

  describe ".call_search_mode" do
    let(:search_response) do
      {
        "message" => "¿Qué tipo de servicio necesitas?",
        "action" => "none",
        "action_data" => {},
        "new_stage" => "searching",
        "updated_context" => {},
        "should_save_message" => false,
        "intent" => nil
      }
    end

    before do
      allow(ClaudeService).to receive(:call).and_return(search_response)
      allow(REDIS).to receive(:get).with("search_state:#{client_phone}").and_return(nil)
      allow(REDIS).to receive(:setex).and_return("OK")
    end

    it "calls ClaudeService with search mode system prompt" do
      described_class.call_search_mode(from: client_phone, body: "Busco un fontanero")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(
          model: :haiku,
          system_prompt: a_string_matching(/plataforma que conecta clientes con técnicos/),
          user_message: "Busco un fontanero"
        )
      )
    end

    it "sends reply to client" do
      described_class.call_search_mode(from: client_phone, body: "Busco un fontanero")

      expect(WhatsAppService).to have_received(:send_message).with(
        to: client_phone,
        message: search_response["message"]
      )
    end

    it "saves search context in Redis" do
      described_class.call_search_mode(from: client_phone, body: "Busco un fontanero")

      expect(REDIS).to have_received(:setex).with(
        "search_state:#{client_phone}",
        86_400,
        anything
      )
    end

    context "when search finds a single provider" do
      let(:found_provider) do
        instance_double(
          Provider,
          id: 2,
          name: "Carlos Ruiz",
          phone: "5212215551234",
          city: "Veracruz",
          short_uuid: "b4e9d3f2"
        )
      end

      let(:found_categories) { double("categories", pluck: ["Fontanero"]) }

      let(:search_response) do
        {
          "message" => "Encontré un fontanero en Veracruz.",
          "action" => "search_provider",
          "action_data" => { "category" => "fontanero", "city" => "veracruz" },
          "new_stage" => "searching",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      let(:search_scope) { double("search_scope") }

      before do
        allow(Provider).to receive(:where).with(active: true).and_return(search_scope)
        allow(search_scope).to receive(:where).and_return(search_scope)
        allow(search_scope).to receive(:joins).and_return(search_scope)
        allow(search_scope).to receive(:distinct).and_return(search_scope)
        allow(search_scope).to receive(:limit).with(5).and_return([found_provider])
        allow(search_scope).to receive(:one?).and_return(true)
        allow(search_scope).to receive(:first).and_return(found_provider)
        allow(found_provider).to receive(:provider_categories).and_return(found_categories)
        allow(found_categories).to receive(:pluck).with(:name).and_return(["Fontanero"])
        allow(REDIS).to receive(:del).and_return(1)
      end

      it "transitions to provider conversation when single match found" do
        described_class.call_search_mode(from: client_phone, body: "Fontanero en Veracruz")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/Elisa.*asistente de Carlos Ruiz/)
        )
      end

      it "cleans up search state from Redis" do
        described_class.call_search_mode(from: client_phone, body: "Fontanero en Veracruz")

        expect(REDIS).to have_received(:del).with("search_state:#{client_phone}")
      end
    end
  end

  describe "review stats in prompt" do
    context "when provider has no reviews" do
      before do
        allow(reviews_relation).to receive(:count).and_return(0)
        allow(reviews_relation).to receive(:average).with(:rating).and_return(nil)
      end

      it "indicates no rating yet" do
        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(ClaudeService).to have_received(:call).with(
          hash_including(system_prompt: a_string_matching(/Sin calificación aún/))
        )
      end
    end
  end

  describe "photo categories in prompt" do
    context "when provider has work photos with tags" do
      before do
        allow(photos_relation).to receive(:pluck).with(:category_tags).and_return([["electricista", "panel"], ["fontanero"]])
      end

      it "includes photo categories in system prompt" do
        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(ClaudeService).to have_received(:call).with(
          hash_including(system_prompt: a_string_matching(/electricista.*panel.*fontanero/))
        )
      end
    end

    context "when provider has no work photos" do
      before do
        allow(photos_relation).to receive(:pluck).with(:category_tags).and_return([])
      end

      it "indicates no photos available" do
        described_class.call(provider: provider, from: client_phone, body: "Hola")

        expect(ClaudeService).to have_received(:call).with(
          hash_including(system_prompt: a_string_matching(/No tiene fotos de trabajo aún/))
        )
      end
    end
  end

  describe "nil from handling" do
    context "when from is nil" do
      it "does not attempt to find a client" do
        allow(Client).to receive(:find_or_initialize_by)

        # from: nil comes from ConversationHandler.route_to_client
        # which passes nil when the client phone is unknown
        described_class.call(provider: provider, from: nil, body: "a3f8c2d1")

        expect(Client).not_to have_received(:find_or_initialize_by)
      end
    end
  end
end
