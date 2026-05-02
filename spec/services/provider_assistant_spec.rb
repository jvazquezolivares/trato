# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProviderAssistant do
  let(:provider) { instance_double(Provider, id: 1, name: "Miguel García", phone: "5212211234567", city: "Veracruz", short_uuid: "a3f8c2d1") }
  let(:conversation) { instance_double(Conversation, id: 1, context: {}, messages: messages_relation, "stage=" => nil, "context=" => nil, "last_message_at=" => nil) }
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

  let(:provider_categories_relation) { double("categories_relation", pluck: ["Fontanero"]) }
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
    allow(clients_limit).to receive(:pluck).and_return(["Martínez"])

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
      it "does not call JobRegistrationService, WorkDayService, or TaskService" do
        allow(JobRegistrationService).to receive(:call)
        allow(Assistants::WorkDayService).to receive(:call)
        allow(Assistants::TaskService).to receive(:call)

        described_class.call(provider: provider, body: "Hola")

        expect(JobRegistrationService).not_to have_received(:call)
        expect(Assistants::WorkDayService).not_to have_received(:call)
        expect(Assistants::TaskService).not_to have_received(:call)
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
  end

  describe "conversation context" do
    let(:message_double) do
      instance_double(Message, direction: "inbound", body: "Terminé un trabajo", created_at: 1.hour.ago)
    end

    let(:limited_messages) { [message_double] }

    it "builds history from recent messages" do
      described_class.call(provider: provider, body: "Hola")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(
          context: hash_including(
            "history" => [{ "role" => "user", "content" => "Terminé un trabajo" }]
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
end
