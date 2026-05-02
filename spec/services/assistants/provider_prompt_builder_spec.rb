# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::ProviderPromptBuilder do
  let(:provider) do
    instance_double(
      Provider,
      id: 1, name: "Miguel García", phone: "5212211234567",
      city: "Veracruz", facebook_token: nil
    )
  end

  let(:conversation) { instance_double(Conversation, id: 1, context: {}, messages: messages_relation) }
  let(:messages_relation) { double("messages_relation") }
  let(:ordered_messages) { double("ordered_messages") }

  let(:provider_categories_relation) { double("categories_relation") }
  let(:clients_relation) { double("clients_relation") }
  let(:jobs_relation) { double("jobs_relation") }

  before do
    allow(provider).to receive(:provider_categories).and_return(provider_categories_relation)
    allow(provider_categories_relation).to receive(:pluck).with(:name).and_return([ "Fontanero" ])

    # Stub clients chain
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

    # Stub jobs chain
    jobs_includes = double("jobs_includes")
    allow(provider).to receive(:jobs).and_return(jobs_includes)
    allow(jobs_includes).to receive(:includes).and_return(jobs_includes)
    allow(jobs_includes).to receive(:order).and_return(jobs_includes)
    allow(jobs_includes).to receive(:limit).and_return([])

    # Stub work_days chain
    work_days_relation = double("work_days_relation")
    allow(provider).to receive(:work_days).and_return(work_days_relation)
    allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(nil)

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

    allow(messages_relation).to receive(:order).and_return(ordered_messages)
    allow(ordered_messages).to receive(:limit).and_return([])
  end

  describe ".call" do
    it "returns a hash with system_prompt and context" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result).to have_key(:system_prompt)
      expect(result).to have_key(:context)
    end

    it "includes Elisa in system prompt" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("Elisa")
    end

    it "includes provider name" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("Miguel García")
    end

    it "includes provider categories" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("Fontanero")
    end

    it "includes recent client names" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("Martínez")
    end

    it "includes history in context" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:context]).to have_key("history")
    end

    it "includes update_work_day action in prompt" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("update_work_day")
    end

    it "includes work day instructions in prompt" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("JORNADA DE TRABAJO")
    end

    context "when no WorkDay exists for today" do
      it "shows 'no registrada aún' in prompt" do
        result = described_class.call(provider: provider, conversation: conversation)

        expect(result[:system_prompt]).to include("no registrada aún")
      end
    end

    context "when a WorkDay exists for today" do
      let(:work_day) do
        instance_double(
          WorkDay,
          status: "active",
          starts_at: Time.zone.parse("08:00"),
          ends_at: Time.zone.parse("18:00"),
          notes: "Cita a las 10"
        )
      end

      before do
        work_days_relation = double("work_days_relation")
        allow(provider).to receive(:work_days).and_return(work_days_relation)
        allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(work_day)
      end

      it "includes work day status in prompt" do
        result = described_class.call(provider: provider, conversation: conversation)

        expect(result[:system_prompt]).to include("estado: active")
      end

      it "includes work day times in prompt" do
        result = described_class.call(provider: provider, conversation: conversation)

        expect(result[:system_prompt]).to include("inicio: 08:00")
        expect(result[:system_prompt]).to include("fin: 18:00")
      end

      it "includes work day notes in prompt" do
        result = described_class.call(provider: provider, conversation: conversation)

        expect(result[:system_prompt]).to include("Cita a las 10")
      end
    end

    it "includes create_task action in prompt" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("create_task")
    end

    it "includes task management instructions in prompt" do
      result = described_class.call(provider: provider, conversation: conversation)

      expect(result[:system_prompt]).to include("TAREAS Y PENDIENTES")
    end

    it "includes task intent keywords in prompt" do
      result = described_class.call(provider: provider, conversation: conversation)

      prompt = result[:system_prompt]
      expect(prompt).to include("tengo que")
      expect(prompt).to include("recuérdame")
      expect(prompt).to include("no se me olvide")
      expect(prompt).to include("no es lista exhaustiva")
    end

    context "when provider has no pending tasks" do
      it "shows 'ninguno' for pending tasks" do
        result = described_class.call(provider: provider, conversation: conversation)

        expect(result[:system_prompt]).to include("Pendientes actuales: ninguno")
      end
    end

    context "when provider has pending tasks" do
      before do
        tasks_relation = double("tasks_relation")
        tasks_pending = double("tasks_pending")
        tasks_ordered = double("tasks_ordered")
        tasks_limited = double("tasks_limited")
        allow(provider).to receive(:tasks).and_return(tasks_relation)
        allow(tasks_relation).to receive(:where).with(status: "pending").and_return(tasks_pending)
        allow(tasks_pending).to receive(:order).and_return(tasks_ordered)
        allow(tasks_ordered).to receive(:limit).and_return(tasks_limited)
        allow(tasks_limited).to receive(:pluck).with(:description).and_return(
          [ "Llamar al señor Pérez", "Comprar cable calibre 12" ]
        )
      end

      it "includes pending task descriptions in prompt" do
        result = described_class.call(provider: provider, conversation: conversation)

        expect(result[:system_prompt]).to include("Llamar al señor Pérez")
        expect(result[:system_prompt]).to include("Comprar cable calibre 12")
      end

      it "formats pending tasks as bullet list" do
        result = described_class.call(provider: provider, conversation: conversation)

        expect(result[:system_prompt]).to include("• Llamar al señor Pérez")
        expect(result[:system_prompt]).to include("• Comprar cable calibre 12")
      end
    end
  end
end
