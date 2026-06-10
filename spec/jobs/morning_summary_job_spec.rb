# frozen_string_literal: true

require "rails_helper"

RSpec.describe MorningSummaryJob, type: :job do
  let(:mexico_city_tz) { ActiveSupport::TimeZone["America/Mexico_City"] }
  let(:today) { Date.new(2025, 4, 15) }

  before do
    allow(Time).to receive(:current).and_return(mexico_city_tz.local(2025, 4, 15, 8, 0, 0))
    allow(WhatsAppService).to receive(:send_template_message)
  end

  # Stubs the ActiveRecord query chain used by the job to find eligible providers.
  # Returns a relation-like object that yields the given providers via find_each.
  def stub_eligible_providers(*providers)
    final_scope = double("final_scope")
    where_chain = double("where_chain")

    active_scope = double("active_scope")
    allow(Provider).to receive(:where).with(active: true).and_return(active_scope)
    allow(active_scope).to receive(:where).and_return(where_chain)
    allow(where_chain).to receive(:not).and_return(final_scope)

    enumerator = allow(final_scope).to receive(:find_each)
    providers.each { |p| enumerator.and_yield(p) }
  end

  # Stubs the pending tasks query for a provider
  def stub_pending_tasks(provider, tasks)
    tasks_relation = double("tasks_relation")
    pending_scope = double("pending_scope")

    allow(provider).to receive(:tasks).and_return(tasks_relation)
    allow(tasks_relation).to receive(:where).with(status: "pending").and_return(pending_scope)
    allow(pending_scope).to receive(:where).and_return(tasks)
  end

  describe "#perform" do
    context "when an active provider has no WorkDay for today" do
      let(:provider) do
        instance_double(Provider, id: 1, name: "Miguel García", phone: "5212211234567")
      end

      before do
        stub_eligible_providers(provider)
        stub_pending_tasks(provider, [])
      end

      it "sends a morning message template via WhatsAppService" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "morning_summary",
          parameters: ["Miguel García", a_string_including("¿Tienes pendientes para hoy?")],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end
    end

    context "when an active provider already has a WorkDay for today (idempotency)" do
      before do
        stub_eligible_providers # yields nothing
      end

      it "does not send any message" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform
      end
    end

    context "when the provider is inactive" do
      before do
        stub_eligible_providers # yields nothing — inactive providers excluded by query
      end

      it "does not send any message" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform
      end
    end

    context "when the provider has pending tasks from the previous day" do
      let(:provider) do
        instance_double(Provider, id: 2, name: "Carlos López", phone: "5212219876543")
      end
      let(:task_one) { instance_double(Task, description: "Llamar al señor Pérez") }
      let(:task_two) { instance_double(Task, description: "Comprar cable calibre 12") }

      before do
        stub_eligible_providers(provider)
        stub_pending_tasks(provider, [ task_one, task_two ])
      end

      it "includes the pending tasks in the summary parameter" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212219876543",
          template_name: "morning_summary",
          parameters: [
            "Carlos López",
            a_string_including("Llamar al señor Pérez", "Comprar cable calibre 12")
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end

      it "shows the count of pending tasks in the summary" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212219876543",
          template_name: "morning_summary",
          parameters: [
            "Carlos López",
            a_string_including("2 pendientes de ayer")
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end

      it "formats tasks as a bullet list" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212219876543",
          template_name: "morning_summary",
          parameters: [
            "Carlos López",
            a_string_including("• Llamar al señor Pérez", "• Comprar cable calibre 12")
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end
    end

    context "when the provider has a single pending task" do
      let(:provider) do
        instance_double(Provider, id: 3, name: "Ana Ruiz", phone: "5212215551234")
      end
      let(:single_task) { instance_double(Task, description: "Revisar presupuesto") }

      before do
        stub_eligible_providers(provider)
        stub_pending_tasks(provider, [ single_task ])
      end

      it "uses singular form for one pending task" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212215551234",
          template_name: "morning_summary",
          parameters: [
            "Ana Ruiz",
            a_string_including("1 pendiente de ayer")
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end
    end

    context "when the provider has no pending tasks" do
      let(:provider) do
        instance_double(Provider, id: 4, name: "Roberto Díaz", phone: "5212218889999")
      end

      before do
        stub_eligible_providers(provider)
        stub_pending_tasks(provider, [])
      end

      it "sends a greeting without task list" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212218889999",
          template_name: "morning_summary",
          parameters: [
            "Roberto Díaz",
            a_string_including("¿Tienes pendientes para hoy?")
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end

      it "does not mention pendientes de ayer" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          expect(args[:parameters][1]).not_to include("pendientes de ayer")
        end

        described_class.new.perform
      end

      it "still asks about new tasks for today" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212218889999",
          template_name: "morning_summary",
          parameters: [
            "Roberto Díaz",
            a_string_including("Menciónamelos para registrarlos")
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end
    end

    context "when multiple active providers need summaries" do
      let(:provider_one) do
        instance_double(Provider, id: 5, name: "Miguel García", phone: "5212211111111")
      end
      let(:provider_two) do
        instance_double(Provider, id: 6, name: "Carlos López", phone: "5212222222222")
      end

      before do
        stub_eligible_providers(provider_one, provider_two)
        stub_pending_tasks(provider_one, [])
        stub_pending_tasks(provider_two, [])
      end

      it "sends a message to each provider" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211111111",
          template_name: "morning_summary",
          parameters: ["Miguel García", anything],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212222222222",
          template_name: "morning_summary",
          parameters: ["Carlos López", anything],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end
    end
  end

  describe "summary text tone and format" do
    let(:provider) do
      instance_double(Provider, id: 7, name: "Test Provider", phone: "5212210000000")
    end

    before do
      stub_eligible_providers(provider)
    end

    context "when there are no pending tasks" do
      before { stub_pending_tasks(provider, []) }

      it "generates a simple summary asking about tasks" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          summary_text = args[:parameters][1]
          expect(summary_text).to include("¿Tienes pendientes para hoy?")
        end

        described_class.new.perform
      end
    end

    context "when there are pending tasks" do
      let(:tasks) do
        (1..3).map { |i| instance_double(Task, description: "Tarea #{i}") }
      end

      before { stub_pending_tasks(provider, tasks) }

      it "includes pending task count and list" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          summary_text = args[:parameters][1]
          expect(summary_text).to include("3 pendientes")
          expect(summary_text).to include("• Tarea 1")
        end

        described_class.new.perform
      end
    end
  end
end
