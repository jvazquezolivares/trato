# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentReminderJob, type: :job do
  before do
    allow(WhatsAppService).to receive(:send_template_message)
  end

  # Stubs the query chain for providers_with_outstanding_jobs
  def stub_providers_with_outstanding_jobs(*providers)
    final_scope = double("final_scope")
    where_chain = double("where_chain")

    allow(Provider).to receive(:where).with(active: true).and_return(where_chain)
    allow(where_chain).to receive(:where).and_return(final_scope)

    enumerator = allow(final_scope).to receive(:find_each)
    providers.each { |p| enumerator.and_yield(p) }
  end

  # Stubs the outstanding jobs for a provider
  def stub_outstanding_jobs(provider, jobs)
    jobs_relation = double("jobs_relation")
    eager_loaded = double("eager_loaded")

    allow(provider).to receive(:jobs).and_return(jobs_relation)
    allow(jobs_relation).to receive(:where).with(status: %w[pending partial]).and_return(eager_loaded)
    allow(eager_loaded).to receive(:eager_load).with(:client).and_return(jobs)
  end

  describe "#perform" do
    context "when a provider has no outstanding jobs" do
      let(:provider_no_jobs) do
        instance_double(Provider, id: 1, name: "Miguel García", phone: "5212211234567")
      end

      before do
        stub_providers_with_outstanding_jobs(provider_no_jobs)
        stub_outstanding_jobs(provider_no_jobs, [])
      end

      it "does not send any message" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform
      end
    end

    context "when a provider has outstanding jobs" do
      let(:provider) do
        instance_double(Provider, id: 2, name: "Carlos López", phone: "5212219876543")
      end
      let(:client) { instance_double(Client, name: "Juan Pérez") }
      let(:job) do
        instance_double(
          Job,
          amount: 1500.0,
          paid_amount: 0.0,
          client: client
        )
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job])
      end

      it "sends a payment reminder template via WhatsAppService" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212219876543",
          template_name: "payment_reminder",
          parameters: [
            "Carlos López",
            "1500.00",
            a_string_including("Juan Pérez", "1500.00")
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform
      end

      it "includes the total outstanding amount" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          total = args[:parameters][1]
          expect(total).to eq("1500.00")
        end

        described_class.new.perform
      end

      it "includes the client name with their outstanding balance" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          client_list = args[:parameters][2]
          expect(client_list).to include("Juan Pérez")
          expect(client_list).to include("1500.00")
        end

        described_class.new.perform
      end
    end

    context "when a provider has multiple outstanding jobs for the same client" do
      let(:provider) do
        instance_double(Provider, id: 3, name: "Ana Ruiz", phone: "5212215551234")
      end
      let(:client) { instance_double(Client, name: "María González") }
      let(:job_one) do
        instance_double(
          Job,
          amount: 800.0,
          paid_amount: 0.0,
          client: client
        )
      end
      let(:job_two) do
        instance_double(
          Job,
          amount: 1200.0,
          paid_amount: 0.0,
          client: client
        )
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job_one, job_two])
      end

      it "sums the outstanding amounts for the same client" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          client_list = args[:parameters][2]
          expect(client_list).to include("María González")
          expect(client_list).to include("2000.00")
        end

        described_class.new.perform
      end

      it "shows the total outstanding across all jobs" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          total = args[:parameters][1]
          expect(total).to eq("2000.00")
        end

        described_class.new.perform
      end
    end

    context "when a provider has outstanding jobs for different clients" do
      let(:provider) do
        instance_double(Provider, id: 4, name: "Roberto Díaz", phone: "5212218889999")
      end
      let(:client_one) { instance_double(Client, name: "Pedro Ramírez") }
      let(:client_two) { instance_double(Client, name: "Laura Hernández") }
      let(:client_three) { instance_double(Client, name: "Sofia Martínez") }

      let(:job_one) do
        instance_double(Job, amount: 500.0, paid_amount: 0.0, client: client_one)
      end
      let(:job_two) do
        instance_double(Job, amount: 1000.0, paid_amount: 0.0, client: client_two)
      end
      let(:job_three) do
        instance_double(Job, amount: 750.0, paid_amount: 0.0, client: client_three)
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job_one, job_two, job_three])
      end

      it "lists all clients with their balances" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          client_list = args[:parameters][2]
          expect(client_list).to include("Pedro Ramírez")
          expect(client_list).to include("Laura Hernández")
          expect(client_list).to include("Sofia Martínez")
        end

        described_class.new.perform
      end

      it "shows the combined total for all clients" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          total = args[:parameters][1]
          expect(total).to eq("2250.00")
        end

        described_class.new.perform
      end
    end

    context "when a client has no name" do
      let(:provider) do
        instance_double(Provider, id: 5, name: "Test Provider", phone: "5212210000000")
      end
      let(:client_no_name) { instance_double(Client, name: nil) }
      let(:job) do
        instance_double(
          Job,
          amount: 300.0,
          paid_amount: 0.0,
          client: client_no_name
        )
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job])
      end

      it "uses a fallback name for the client" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          client_list = args[:parameters][2]
          expect(client_list).to include("Cliente sin nombre")
        end

        described_class.new.perform
      end
    end

    context "when a job has partial payment" do
      let(:provider) do
        instance_double(Provider, id: 6, name: "Partial Provider", phone: "5212210001111")
      end
      let(:client) { instance_double(Client, name: "Test Client") }
      let(:job_partial) do
        instance_double(
          Job,
          amount: 1000.0,
          paid_amount: 400.0,
          client: client
        )
      end

      before do
        stub_providers_with_outstanding_jobs(provider)
        stub_outstanding_jobs(provider, [job_partial])
      end

      it "calculates the remaining balance correctly" do
        expect(WhatsAppService).to receive(:send_template_message) do |args|
          client_list = args[:parameters][2]
          expect(client_list).to include("600.00")
        end

        described_class.new.perform
      end
    end
  end
end
