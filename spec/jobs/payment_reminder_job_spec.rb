# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReminderJob, type: :job do
  before do
    allow(WhatsAppService).to receive(:send_message)
  end

  # Stubs the ActiveRecord query chain used by the job to find eligible providers.
  # Returns a relation-like object that yields the given providers via find_each.
  def stub_providers_with_outstanding_jobs(*providers)
    final_scope = double("final_scope")
    active_scope = double("active_scope")

    allow(Provider).to receive(:where).with(active: true).and_return(active_scope)
    allow(active_scope).to receive(:where).and_return(final_scope)

    enumerator = allow(final_scope).to receive(:find_each)
    providers.each { |p| enumerator.and_yield(p) }
  end

  # Stubs the outstanding jobs query for a provider, returning jobs with eager-loaded clients.
  def stub_outstanding_jobs(provider, jobs)
    jobs_relation = double("jobs_relation")
    status_scope = double("status_scope")

    allow(provider).to receive(:jobs).and_return(jobs_relation)
    allow(jobs_relation).to receive(:where)
      .with(status: %w[pending partial])
      .and_return(status_scope)
    allow(status_scope).to receive(:eager_load).with(:client).and_return(jobs)
  end

  describe "#perform" do
    context "when a provider has outstanding jobs" do
      let(:provider) do
        instance_double(Provider, id: 1, name: "Miguel García", phone: "5212211234567")
      end
      let(:client) { instance_double(Client, name: "Mariana López") }
      let(:outstanding_job) do
        instance_double(Job, amount: 2500.0, paid_amount: 1000.0, client: client)
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [outstanding_job])
      end

      it "sends a payment reminder via WhatsAppService" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212211234567",
          message: a_string_including("Miguel García", "Mariana López")
        )

        described_class.new.perform
      end

      it "includes the total outstanding amount" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212211234567",
          message: a_string_including("$1500.00")
        )

        described_class.new.perform
      end

      it "includes the client name with their outstanding balance" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212211234567",
          message: a_string_including("• Mariana López: $1500.00")
        )

        described_class.new.perform
      end
    end

    context "when a provider has no outstanding jobs" do
      let(:provider) do
        instance_double(Provider, id: 2, name: "Carlos López", phone: "5212219876543")
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [])
      end

      it "does not send any message" do
        expect(WhatsAppService).not_to receive(:send_message)

        described_class.new.perform
      end
    end

    context "when outstanding amounts are grouped by client" do
      let(:provider) do
        instance_double(Provider, id: 3, name: "Ana Ruiz", phone: "5212215551234")
      end
      let(:client_one) { instance_double(Client, name: "Mariana López") }
      let(:client_two) { instance_double(Client, name: "Pedro Sánchez") }
      let(:job_one) do
        instance_double(Job, amount: 3000.0, paid_amount: 1000.0, client: client_one)
      end
      let(:job_two) do
        instance_double(Job, amount: 1500.0, paid_amount: 0.0, client: client_two)
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job_one, job_two])
      end

      it "lists each client with their outstanding balance" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212215551234",
          message: a_string_including(
            "• Mariana López: $2000.00",
            "• Pedro Sánchez: $1500.00"
          )
        )

        described_class.new.perform
      end

      it "shows the combined total outstanding" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212215551234",
          message: a_string_including("$3500.00")
        )

        described_class.new.perform
      end
    end

    context "when a provider has multiple outstanding jobs for the same client" do
      let(:provider) do
        instance_double(Provider, id: 4, name: "Roberto Díaz", phone: "5212218889999")
      end
      let(:client) { instance_double(Client, name: "Laura Martínez") }
      let(:job_one) do
        instance_double(Job, amount: 2000.0, paid_amount: 500.0, client: client)
      end
      let(:job_two) do
        instance_double(Job, amount: 1000.0, paid_amount: 0.0, client: client)
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job_one, job_two])
      end

      it "sums the outstanding amounts for the same client" do
        # (2000 - 500) + (1000 - 0) = 2500
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212218889999",
          message: a_string_including("• Laura Martínez: $2500.00")
        )

        described_class.new.perform
      end

      it "shows the total outstanding across all jobs" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212218889999",
          message: a_string_including("$2500.00")
        )

        described_class.new.perform
      end
    end

    context "when a provider has outstanding jobs for different clients" do
      let(:provider) do
        instance_double(Provider, id: 5, name: "Miguel García", phone: "5212211111111")
      end
      let(:client_a) { instance_double(Client, name: "Cliente A") }
      let(:client_b) { instance_double(Client, name: "Cliente B") }
      let(:client_c) { instance_double(Client, name: "Cliente C") }
      let(:job_a) do
        instance_double(Job, amount: 1000.0, paid_amount: 0.0, client: client_a)
      end
      let(:job_b) do
        instance_double(Job, amount: 2000.0, paid_amount: 500.0, client: client_b)
      end
      let(:job_c) do
        instance_double(Job, amount: 500.0, paid_amount: 200.0, client: client_c)
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job_a, job_b, job_c])
      end

      it "lists all three clients with their balances" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212211111111",
          message: a_string_including(
            "• Cliente A: $1000.00",
            "• Cliente B: $1500.00",
            "• Cliente C: $300.00"
          )
        )

        described_class.new.perform
      end

      it "shows the combined total for all clients" do
        # 1000 + 1500 + 300 = 2800
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212211111111",
          message: a_string_including("$2800.00")
        )

        described_class.new.perform
      end
    end

    context "when no providers have outstanding jobs" do
      before do
        stub_providers_with_outstanding_jobs # yields nothing
      end

      it "does not send any message" do
        expect(WhatsAppService).not_to receive(:send_message)

        described_class.new.perform
      end
    end

    context "when a client has no name" do
      let(:provider) do
        instance_double(Provider, id: 6, name: "Test Provider", phone: "5212210000000")
      end
      let(:client_no_name) { instance_double(Client, name: nil) }
      let(:job_no_name) do
        instance_double(Job, amount: 800.0, paid_amount: 0.0, client: client_no_name)
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job_no_name])
      end

      it "uses a fallback name for the client" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212210000000",
          message: a_string_including("• Cliente sin nombre: $800.00")
        )

        described_class.new.perform
      end
    end
  end

  describe "message tone and format" do
    let(:provider) do
      instance_double(Provider, id: 7, name: "Test Provider", phone: "5212210000000")
    end
    let(:client) { instance_double(Client, name: "Test Client") }
    let(:job_record) do
      instance_double(Job, amount: 1000.0, paid_amount: 0.0, client: client)
    end

    before do
      stub_providers_with_outstanding_jobs(provider)
      stub_outstanding_jobs(provider, [job_record])
    end

    it "uses no more than 2 emojis" do
      expect(WhatsAppService).to receive(:send_message) do |args|
        emoji_count = args[:message].scan(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/).size
        expect(emoji_count).to be <= 2
      end

      described_class.new.perform
    end

    it "keeps the message within 5-6 lines" do
      expect(WhatsAppService).to receive(:send_message) do |args|
        line_count = args[:message].split("\n").size
        expect(line_count).to be <= 6
      end

      described_class.new.perform
    end

    it "includes a warm greeting with the provider name" do
      expect(WhatsAppService).to receive(:send_message).with(
        to: "5212210000000",
        message: a_string_starting_with("Hola Test Provider")
      )

      described_class.new.perform
    end
  end
end
