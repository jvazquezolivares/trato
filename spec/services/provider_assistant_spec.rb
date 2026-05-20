# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProviderAssistant do
  let(:provider) { instance_double(Provider, id: 1, name: "Miguel García", phone: "5212211234567", city: "Veracruz", short_uuid: "a3f8c2d1", facebook_token: nil) }
  let(:conversation) { instance_double(Conversation, id: 1, stage: "active", context: {}, messages: messages_relation, "stage=" => nil, "context=" => nil, "last_message_at=" => nil) }
  let(:messages_relation) { double("messages_relation") }
  let(:ordered_messages) { double("ordered_messages") }
  let(:limited_messages) { [] }

  let(:claude_response) do
    {
      "message" => "Registrado ✅ Trabajo con los Martínez por $1,500.",
      "action" => "none",
      "action_data" => {},
      "new_stage" => "active",
      "updated_context" => {},
      "should_save_message" => false,
      "intent" => nil
    }
  end

  let(:provider_categories_relation) { double("categories_relation", pluck: [ "Fontanero" ]) }
  let(:clients_relation) { double("clients_relation") }
  let(:jobs_relation) { double("jobs_relation") }

  before do
    allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
    allow(conversation).to receive(:update!).and_return(true)

    allow(messages_relation).to receive(:order).and_return(ordered_messages)
    allow(ordered_messages).to receive(:limit).and_return(limited_messages)
    allow(messages_relation).to receive(:create!).and_return(true)

    allow(provider).to receive(:provider_categories).and_return(provider_categories_relation)

    # Stub clients chain for recent_client_names
    clients_join = double("clients_join")
    clients_where = double("clients_where")
    clients_order = double("clients_order")
    clients_limit = double("clients_limit")
    allow(provider).to receive(:clients).and_return(clients_join)
    allow(clients_join).to receive(:joins).and_return(clients_where)
    allow(clients_where).to receive(:where).and_return(clients_order)
    allow(clients_order).to receive(:order).and_return(clients_limit)
    allow(clients_limit).to receive(:limit).and_return(clients_limit)
    allow(clients_limit).to receive(:pluck).and_return([ "Martínez" ])

    # Stub jobs chain for recent_jobs_summary
    jobs_includes = double("jobs_includes")
    jobs_order = double("jobs_order")
    allow(provider).to receive(:jobs).and_return(jobs_includes)
    allow(jobs_includes).to receive(:includes).and_return(jobs_order)
    allow(jobs_order).to receive(:order).and_return(jobs_order)
    allow(jobs_order).to receive(:limit).and_return([])

    # Stub work_days chain for today_work_day_summary
    work_days_relation = double("work_days_relation")
    allow(provider).to receive(:work_days).and_return(work_days_relation)
    allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(nil)
    allow(work_days_relation).to receive(:find_or_initialize_by).and_return(instance_double(WorkDay, save!: true))

    # Stub tasks chain for pending_tasks_summary
    tasks_relation = double("tasks_relation")
    tasks_pending = double("tasks_pending")
    tasks_ordered = double("tasks_ordered")
    tasks_limited = double("tasks_limited")
    allow(provider).to receive(:tasks).and_return(tasks_relation)
    allow(tasks_relation).to receive(:where).with(status: "pending").and_return(tasks_pending)
    allow(tasks_pending).to receive(:order).and_return(tasks_ordered)
    allow(tasks_ordered).to receive(:limit).and_return(tasks_limited)
    allow(tasks_limited).to receive(:pluck).with(:description).and_return([])
    allow(tasks_relation).to receive(:create!).and_return(instance_double(Task, id: 1, description: "test"))

    allow(ClaudeService).to receive(:call).and_return(claude_response)
    allow(WhatsAppService).to receive(:send_message).and_return(true)
  end

  describe ".call" do
    it "finds or creates a conversation for the provider" do
      described_class.call(provider: provider, body: "Hola")

      expect(Conversation).to have_received(:find_or_create_by!).with(
        phone: provider.phone,
        provider: provider,
        role: "provider"
      )
    end

    it "calls ClaudeService with haiku model" do
      described_class.call(provider: provider, body: "Terminé un trabajo")

      expect(ClaudeService).to have_received(:call).with(
        model: :haiku,
        system_prompt: a_string_matching(/Elisa.*asistente de negocios de Miguel/),
        user_message: "Terminé un trabajo",
        context: hash_including("history")
      )
    end

    it "sends reply via WhatsAppService" do
      described_class.call(provider: provider, body: "Hola")

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: claude_response["message"]
      )
    end

    it "updates conversation with last_message_at" do
      described_class.call(provider: provider, body: "Hola")

      expect(conversation).to have_received(:update!).with(
        hash_including(:last_message_at)
      )
    end

    it "returns the Claude response" do
      result = described_class.call(provider: provider, body: "Hola")

      expect(result).to eq(claude_response)
    end
  end

  describe "message persistence" do
    context "when should_save_message is false" do
      let(:claude_response) do
        {
          "message" => "Ok, entendido.",
          "action" => "none",
          "action_data" => {},
          "new_stage" => nil,
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      it "does not persist the message" do
        described_class.call(provider: provider, body: "ok")

        expect(messages_relation).not_to have_received(:create!)
      end
    end

    context "when should_save_message is true" do
      let(:claude_response) do
        {
          "message" => "Registrado ✅ Trabajo con los Martínez.",
          "action" => "register_job",
          "action_data" => {
            "client_name" => "Martínez",
            "client_phone" => "5212219876543",
            "description" => "Fuga en cocina",
            "amount" => "1500",
            "paid_amount" => "1500",
            "payment_method" => "cash"
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "job_registered"
        }
      end

      before do
        allow(JobRegistrationService).to receive(:call).and_return(nil)
      end

      it "persists the inbound message" do
        described_class.call(provider: provider, body: "Terminé con los Martínez, me pagaron 1500")

        expect(messages_relation).to have_received(:create!).with(
          hash_including(
            direction: "inbound",
            body: "Terminé con los Martínez, me pagaron 1500",
            intent: "job_registered",
            processed: true
          )
        )
      end

      it "persists the outbound reply" do
        described_class.call(provider: provider, body: "Terminé con los Martínez, me pagaron 1500")

        expect(messages_relation).to have_received(:create!).with(
          hash_including(
            direction: "outbound",
            body: claude_response["message"],
            intent: "job_registered",
            processed: true
          )
        )
      end
    end
  end

  describe "action execution" do
    context "when action is register_job" do
      let(:claude_response) do
        {
          "message" => "Registrado ✅",
          "action" => "register_job",
          "action_data" => {
            "client_name" => "Martínez",
            "client_phone" => "5212219876543",
            "description" => "Fuga en cocina",
            "amount" => "1500",
            "paid_amount" => "1500",
            "payment_method" => "cash"
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "job_registered"
        }
      end

      before do
        allow(JobRegistrationService).to receive(:call).and_return(nil)
      end

      it "delegates to JobRegistrationService with register_job action" do
        described_class.call(provider: provider, body: "Terminé con los Martínez")

        expect(JobRegistrationService).to have_received(:call).with(
          provider: provider,
          action: "register_job",
          action_data: claude_response["action_data"]
        )
      end
    end

    context "when action is register_expense" do
      let(:claude_response) do
        {
          "message" => "Gasto registrado 📝",
          "action" => "register_expense",
          "action_data" => {
            "description" => "Cable calibre 12",
            "amount" => "350",
            "payment_method" => "cash",
            "job_id" => nil
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "expense_registered"
        }
      end

      before do
        allow(JobRegistrationService).to receive(:call).and_return(nil)
      end

      it "delegates to JobRegistrationService with register_expense action" do
        described_class.call(provider: provider, body: "Compré cable por 350")

        expect(JobRegistrationService).to have_received(:call).with(
          provider: provider,
          action: "register_expense",
          action_data: claude_response["action_data"]
        )
      end
    end

    context "when action is update_work_day" do
      let(:claude_response) do
        {
          "message" => "Listo, registré tu jornada de hoy 👍",
          "action" => "update_work_day",
          "action_data" => {
            "starts_at" => "08:00",
            "ends_at" => "18:00",
            "status" => "active",
            "notes" => "Cita en Boca del Río a las 10"
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "work_day_updated"
        }
      end

      before do
        allow(Assistants::WorkDayService).to receive(:call).and_return(nil)
      end

      it "delegates to Assistants::WorkDayService" do
        described_class.call(provider: provider, body: "Hoy trabajo de 8 a 6")

        expect(Assistants::WorkDayService).to have_received(:call).with(
          provider: provider,
          action_data: claude_response["action_data"]
        )
      end
    end

    context "when action is create_task" do
      let(:claude_response) do
        {
          "message" => "Listo, registré tu pendiente 📋",
          "action" => "create_task",
          "action_data" => {
            "description" => "Llamar al señor Pérez",
            "priority" => "normal",
            "snoozed_until" => nil
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "task_created"
        }
      end

      before do
        allow(Assistants::TaskService).to receive(:call).and_return(nil)
      end

      it "delegates to Assistants::TaskService" do
        described_class.call(provider: provider, body: "Recuérdame llamar al señor Pérez")

        expect(Assistants::TaskService).to have_received(:call).with(
          provider: provider,
          action_data: claude_response["action_data"]
        )
      end
    end

    context "when action is none" do
      it "does not call JobRegistrationService, WorkDayService, TaskService, SocialMediaService, or FinancialQueryService" do
        allow(JobRegistrationService).to receive(:call)
        allow(Assistants::WorkDayService).to receive(:call)
        allow(Assistants::TaskService).to receive(:call)
        allow(Assistants::SocialMediaService).to receive(:call)
        allow(Assistants::FinancialQueryService).to receive(:call)

        described_class.call(provider: provider, body: "Hola")

        expect(JobRegistrationService).not_to have_received(:call)
        expect(Assistants::WorkDayService).not_to have_received(:call)
        expect(Assistants::TaskService).not_to have_received(:call)
        expect(Assistants::SocialMediaService).not_to have_received(:call)
        expect(Assistants::FinancialQueryService).not_to have_received(:call)
      end
    end

    context "when action is financial_query" do
      let(:claude_response) do
        {
          "message" => "Déjame revisar tus números...",
          "action" => "financial_query",
          "action_data" => {
            "query_type" => "earnings",
            "date_from" => Date.current.to_s,
            "date_to" => Date.current.to_s
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => "financial_query_answered"
        }
      end

      let(:financial_data) do
        {
          "query_type" => "earnings",
          "income" => 3500.0,
          "job_count" => 2,
          "date_from" => Date.current.to_s,
          "date_to" => Date.current.to_s
        }
      end

      let(:presentation_response) do
        {
          "message" => "Hoy llevas $3,500 de ingresos con 2 trabajos 💰",
          "action" => "none",
          "action_data" => {},
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => "financial_query_answered"
        }
      end

      before do
        allow(Assistants::FinancialQueryService).to receive(:call).and_return(financial_data)
        # The second Claude call returns the presentation response
        allow(ClaudeService).to receive(:call).and_return(claude_response, presentation_response)
      end

      it "calls FinancialQueryService with query_type and date range" do
        described_class.call(provider: provider, body: "¿Cuánto llevo hoy?")

        expect(Assistants::FinancialQueryService).to have_received(:call).with(
          provider: provider,
          query_type: "earnings",
          date_from: Date.current.to_s,
          date_to: Date.current.to_s
        )
      end

      it "makes a second Claude call with the computed financial data" do
        described_class.call(provider: provider, body: "¿Cuánto llevo hoy?")

        expect(ClaudeService).to have_received(:call).twice
      end

      it "sends the presentation response message" do
        described_class.call(provider: provider, body: "¿Cuánto llevo hoy?")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: "Hoy llevas $3,500 de ingresos con 2 trabajos 💰"
        )
      end
    end

    context "when financial_query has no date range (ambiguous)" do
      let(:claude_response) do
        {
          "message" => "¿De qué periodo quieres los ingresos?",
          "action" => "financial_query",
          "action_data" => {
            "query_type" => "earnings",
            "date_from" => nil,
            "date_to" => nil
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      before do
        allow(WhatsAppService).to receive(:send_list_message).and_return(true)
      end

      it "sends a List Message with financial options" do
        described_class.call(provider: provider, body: "¿Cuánto he ganado?")

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: provider.phone,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "¿Qué quieres ver?")
          )
        )
      end

      it "updates conversation stage to awaiting_financial_selection" do
        described_class.call(provider: provider, body: "¿Cuánto he ganado?")

        expect(conversation).to have_received(:update!).with(stage: "awaiting_financial_selection")
      end

      it "does not call FinancialQueryService" do
        allow(Assistants::FinancialQueryService).to receive(:call)

        described_class.call(provider: provider, body: "¿Cuánto he ganado?")

        expect(Assistants::FinancialQueryService).not_to have_received(:call)
      end
    end

    context "when financial_query service returns an error" do
      let(:claude_response) do
        {
          "message" => "No pude obtener los datos financieros",
          "action" => "financial_query",
          "action_data" => {
            "query_type" => "earnings",
            "date_from" => "2026-05-01",
            "date_to" => "2026-05-20"
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      before do
        allow(Assistants::FinancialQueryService).to receive(:call).and_return(
          { "error" => "Database connection failed" }
        )
      end

      it "falls back to the first Claude response message" do
        described_class.call(provider: provider, body: "¿Cuánto gané este mes?")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: "No pude obtener los datos financieros"
        )
      end

      it "does not make a second Claude call" do
        described_class.call(provider: provider, body: "¿Cuánto gané este mes?")

        expect(ClaudeService).to have_received(:call).once
      end
    end

    context "when action is initiate_social_post" do
      let(:claude_response) do
        {
          "message" => "¿Quieres publicar esta foto en tus redes sociales?",
          "action" => "initiate_social_post",
          "action_data" => {
            "photo_url" => "https://trato-photos.s3.amazonaws.com/photos/panel.jpg",
            "description" => "Panel eléctrico"
          },
          "new_stage" => "social_media_flow",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      before do
        allow(Assistants::SocialMediaService).to receive(:call).and_return(nil)
      end

      it "delegates to Assistants::SocialMediaService" do
        described_class.call(provider: provider, body: "Mira esta foto", media_url: "https://example.com/photo.jpg")

        expect(Assistants::SocialMediaService).to have_received(:call).with(
          provider: provider,
          action: "initiate_social_post",
          action_data: claude_response["action_data"]
        )
      end
    end

    context "when action is generate_caption" do
      let(:claude_response) do
        {
          "message" => "Aquí va el pie de foto: ¡Trabajo terminado! 🔌",
          "action" => "generate_caption",
          "action_data" => {
            "photo_url" => "https://trato-photos.s3.amazonaws.com/photos/panel.jpg",
            "description" => "Panel eléctrico residencial"
          },
          "new_stage" => "social_media_flow",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      before do
        allow(Assistants::SocialMediaService).to receive(:call).and_return(nil)
      end

      it "delegates to Assistants::SocialMediaService" do
        described_class.call(provider: provider, body: "Panel eléctrico residencial")

        expect(Assistants::SocialMediaService).to have_received(:call).with(
          provider: provider,
          action: "generate_caption",
          action_data: claude_response["action_data"]
        )
      end
    end

    context "when action is approve_caption" do
      let(:claude_response) do
        {
          "message" => "¡Publicando tu foto! 🎉",
          "action" => "approve_caption",
          "action_data" => {
            "photo_id" => "10",
            "caption" => "¡Trabajo terminado! 🔌 #Electricista"
          },
          "new_stage" => "active",
          "updated_context" => {},
          "should_save_message" => true,
          "intent" => "social_post_published"
        }
      end

      before do
        allow(Assistants::SocialMediaService).to receive(:call).and_return(nil)
      end

      it "delegates to Assistants::SocialMediaService" do
        described_class.call(provider: provider, body: "Sí, publícala")

        expect(Assistants::SocialMediaService).to have_received(:call).with(
          provider: provider,
          action: "approve_caption",
          action_data: claude_response["action_data"]
        )
      end
    end
  end

  describe "system prompt" do
    it "includes provider name in the prompt" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Miguel García/))
      )
    end

    it "includes provider categories" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Fontanero/))
      )
    end

    it "includes provider city" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Veracruz/))
      )
    end

    it "includes recent client names" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Martínez/))
      )
    end

    it "includes social media instructions in the prompt" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/PUBLICACIÓN EN REDES SOCIALES/))
      )
    end

    it "includes financial query instructions in the prompt" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/CONSULTAS FINANCIERAS/))
      )
    end

    it "includes today's date in the prompt for financial queries" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Fecha de hoy: #{Date.current}/))
      )
    end

    it "includes facebook connection status in the prompt" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(system_prompt: a_string_matching(/Facebook conectado: no/))
      )
    end
  end

  describe "conversation context" do
    let(:message_double) do
      instance_double(Message, direction: "inbound", body: "Terminé un trabajo", created_at: 1.hour.ago)
    end

    let(:limited_messages) { [ message_double ] }

    it "builds history from recent messages" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(
          context: hash_including(
            "history" => [ { "role" => "user", "content" => "Terminé un trabajo" } ]
          )
        )
      )
    end
  end

  describe "conversation stage update" do
    context "when Claude returns a new_stage" do
      let(:claude_response) do
        {
          "message" => "¿Cómo se llama el cliente?",
          "action" => "none",
          "action_data" => {},
          "new_stage" => "collecting_job_info",
          "updated_context" => { "collecting" => "client_name" },
          "should_save_message" => false,
          "intent" => nil
        }
      end

      it "updates conversation stage" do
        described_class.call(provider: provider, body: "Terminé un trabajo")

        expect(conversation).to have_received(:update!).with(
          hash_including(stage: "collecting_job_info")
        )
      end

      it "updates conversation context" do
        described_class.call(provider: provider, body: "Terminé un trabajo")

        expect(conversation).to have_received(:update!).with(
          hash_including(context: { "collecting" => "client_name" })
        )
      end
    end
  end

  describe "financial options List Message flow" do
    context "when conversation stage is awaiting_financial_selection" do
      let(:conversation) do
        instance_double(
          Conversation,
          id: 1,
          stage: "awaiting_financial_selection",
          context: {},
          messages: messages_relation,
          "stage=" => nil,
          "context=" => nil,
          "last_message_at=" => nil
        )
      end

      before do
        allow(conversation).to receive(:update!).and_return(true)
        allow(Assistants::FinancialQueryService).to receive(:call).and_return({
          "query_type" => "earnings",
          "total" => 5000,
          "count" => 3
        })
      end

      context "when provider selects 'Ver ingresos'" do
        it "calls FinancialQueryService with earnings query for current month" do
          described_class.call(provider: provider, body: "income")

          expect(Assistants::FinancialQueryService).to have_received(:call).with(
            provider: provider,
            query_type: "earnings",
            date_from: Date.current.beginning_of_month.to_s,
            date_to: Date.current.to_s
          )
        end

        it "resets conversation stage to active" do
          described_class.call(provider: provider, body: "income")

          expect(conversation).to have_received(:update!).with(stage: "active")
        end

        it "sends a conversational response with financial data" do
          described_class.call(provider: provider, body: "income")

          expect(WhatsAppService).to have_received(:send_message).with(
            to: provider.phone,
            message: a_string_matching(/.+/)
          )
        end
      end

      context "when provider selects 'Ver gastos'" do
        it "calls FinancialQueryService with expenses query for current month" do
          described_class.call(provider: provider, body: "expenses")

          expect(Assistants::FinancialQueryService).to have_received(:call).with(
            provider: provider,
            query_type: "expenses",
            date_from: Date.current.beginning_of_month.to_s,
            date_to: Date.current.to_s
          )
        end
      end

      context "when provider selects 'Ver cobros pendientes'" do
        it "calls FinancialQueryService with outstanding query" do
          described_class.call(provider: provider, body: "pending")

          expect(Assistants::FinancialQueryService).to have_received(:call).with(
            provider: provider,
            query_type: "outstanding",
            date_from: nil,
            date_to: nil
          )
        end
      end

      context "when provider selects 'No, gracias'" do
        it "does not call FinancialQueryService" do
          described_class.call(provider: provider, body: "no_thanks")

          expect(Assistants::FinancialQueryService).not_to have_received(:call)
        end

        it "resets conversation stage to active" do
          described_class.call(provider: provider, body: "no_thanks")

          expect(conversation).to have_received(:update!).with(stage: "active")
        end

        it "sends a friendly acknowledgment message" do
          described_class.call(provider: provider, body: "no_thanks")

          expect(WhatsAppService).to have_received(:send_message).with(
            to: provider.phone,
            message: "Perfecto, aquí estoy si necesitas algo más 😊"
          )
        end
      end

      context "when selection ID is uppercase" do
        it "normalizes to lowercase and processes correctly" do
          described_class.call(provider: provider, body: "INCOME")

          expect(Assistants::FinancialQueryService).to have_received(:call).with(
            hash_including(query_type: "earnings")
          )
        end
      end

      context "when selection ID has whitespace" do
        it "strips whitespace and processes correctly" do
          described_class.call(provider: provider, body: "  expenses  ")

          expect(Assistants::FinancialQueryService).to have_received(:call).with(
            hash_including(query_type: "expenses")
          )
        end
      end
    end

    context "when financial query is ambiguous (no date range)" do
      let(:claude_response) do
        {
          "message" => "¿Qué quieres ver?",
          "action" => "financial_query",
          "action_data" => {
            "query_type" => "earnings",
            "date_from" => nil,
            "date_to" => nil
          },
          "new_stage" => nil,
          "updated_context" => {},
          "should_save_message" => false
        }
      end

      before do
        allow(WhatsApp::ListMessageBuilder).to receive(:build_financial_options_list).and_return({
          type: "list",
          action: { button: "Ver opciones" }
        })
        allow(WhatsAppService).to receive(:send_list_message).and_return(true)
      end

      it "sends financial options List Message" do
        described_class.call(provider: provider, body: "¿Cuánto he ganado?")

        expect(WhatsApp::ListMessageBuilder).to have_received(:build_financial_options_list)
        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: provider.phone,
          payload: hash_including(type: "list")
        )
      end

      it "updates conversation stage to awaiting_financial_selection" do
        described_class.call(provider: provider, body: "¿Cuánto he ganado?")

        expect(conversation).to have_received(:update!).with(stage: "awaiting_financial_selection")
      end

      it "does not call FinancialQueryService yet" do
        allow(Assistants::FinancialQueryService).to receive(:call)

        described_class.call(provider: provider, body: "¿Cuánto he ganado?")

        expect(Assistants::FinancialQueryService).not_to have_received(:call)
      end
    end

    context "when financial query has specific date range" do
      let(:claude_response) do
        {
          "message" => "Aquí están tus ingresos",
          "action" => "financial_query",
          "action_data" => {
            "query_type" => "earnings",
            "date_from" => "2026-05-01",
            "date_to" => "2026-05-20"
          },
          "new_stage" => nil,
          "updated_context" => {},
          "should_save_message" => false
        }
      end

      before do
        allow(Assistants::FinancialQueryService).to receive(:call).and_return({
          "query_type" => "earnings",
          "total" => 5000,
          "count" => 3
        })
      end

      it "does not send List Message" do
        allow(WhatsAppService).to receive(:send_list_message)

        described_class.call(provider: provider, body: "¿Cuánto gané en mayo?")

        expect(WhatsAppService).not_to have_received(:send_list_message)
      end

      it "calls FinancialQueryService directly with date range" do
        described_class.call(provider: provider, body: "¿Cuánto gané en mayo?")

        expect(Assistants::FinancialQueryService).to have_received(:call).with(
          provider: provider,
          query_type: "earnings",
          date_from: "2026-05-01",
          date_to: "2026-05-20"
        )
      end
    end

    context "when financial query is for outstanding (no dates needed)" do
      let(:claude_response) do
        {
          "message" => "Aquí están tus cobros pendientes",
          "action" => "financial_query",
          "action_data" => {
            "query_type" => "outstanding",
            "date_from" => nil,
            "date_to" => nil
          },
          "new_stage" => nil,
          "updated_context" => {},
          "should_save_message" => false
        }
      end

      before do
        allow(Assistants::FinancialQueryService).to receive(:call).and_return({
          "query_type" => "outstanding",
          "total" => 2000,
          "count" => 2
        })
      end

      it "does not send List Message (outstanding queries don't need dates)" do
        allow(WhatsAppService).to receive(:send_list_message)

        described_class.call(provider: provider, body: "¿Qué me deben?")

        expect(WhatsAppService).not_to have_received(:send_list_message)
      end

      it "calls FinancialQueryService directly" do
        described_class.call(provider: provider, body: "¿Qué me deben?")

        expect(Assistants::FinancialQueryService).to have_received(:call).with(
          provider: provider,
          query_type: "outstanding",
          date_from: nil,
          date_to: nil
        )
      end
    end
  end
end
