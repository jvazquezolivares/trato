# frozen_string_literal: true

require "rails_helper"

RSpec.describe JobRegistrationService do
  let(:provider) { instance_double(Provider, id: 1) }
  let(:client) { instance_double(Client, id: 42, name: "Martínez", phone: "5212219876543") }
  let(:job_double) { instance_double(Job, id: 8, paid_amount: BigDecimal("1500"), status: "paid", description: "Fuga en cocina", payment_method: "cash", client: client) }
  let(:provider_jobs) { double("provider_jobs") }

  before do
    allow(ClientLookupService).to receive(:call).and_return(client)
    allow(Job).to receive(:create!).and_return(job_double)
    allow(Transaction).to receive(:create!).and_return(true)
    allow(ReviewRequestJob).to receive(:perform_later).and_return(true)
    allow(provider).to receive(:jobs).and_return(provider_jobs)
  end

  describe "Case 1: Known client, full payment" do
    let(:action_data) do
      {
        "client_name" => "Martínez",
        "client_phone" => "5212219876543",
        "description" => "Fuga en cocina",
        "amount" => "1500",
        "paid_amount" => "1500",
        "payment_method" => "cash"
      }
    end

    it "looks up the client via ClientLookupService" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(ClientLookupService).to have_received(:call).with(
        phone: "5212219876543",
        name: "Martínez",
        provider: provider
      )
    end

    it "creates a Job with status paid" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(Job).to have_received(:create!).with(
        hash_including(
          provider: provider,
          client: client,
          description: "Fuga en cocina",
          amount: BigDecimal("1500"),
          paid_amount: BigDecimal("1500"),
          status: "paid",
          payment_method: "cash"
        )
      )
    end

    it "creates an income Transaction" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(Transaction).to have_received(:create!).with(
        hash_including(
          provider: provider,
          job: job_double,
          client: client,
          amount: BigDecimal("1500"),
          transaction_type: "income",
          payment_method: "cash"
        )
      )
    end

    it "enqueues ReviewRequestJob" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(ReviewRequestJob).to have_received(:perform_later).with(8)
    end
  end

  describe "Case 2: Unknown client" do
    let(:action_data) do
      {
        "client_name" => "López",
        "client_phone" => "5212218765432",
        "description" => "Instalación de contactos",
        "amount" => "2500",
        "paid_amount" => "2500",
        "payment_method" => "transfer"
      }
    end

    it "delegates client creation to ClientLookupService" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(ClientLookupService).to have_received(:call).with(
        phone: "5212218765432",
        name: "López",
        provider: provider
      )
    end
  end

  describe "Case 3: Partial payment" do
    let(:partial_job) { instance_double(Job, id: 9, paid_amount: BigDecimal("1000"), status: "partial", description: "Panel eléctrico", payment_method: "cash", client: client) }

    let(:action_data) do
      {
        "client_name" => "Martínez",
        "client_phone" => "5212219876543",
        "description" => "Panel eléctrico",
        "amount" => "2500",
        "paid_amount" => "1000",
        "payment_method" => "cash"
      }
    end

    before do
      allow(Job).to receive(:create!).and_return(partial_job)
    end

    it "creates a Job with status partial" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(Job).to have_received(:create!).with(
        hash_including(
          status: "partial",
          amount: BigDecimal("2500"),
          paid_amount: BigDecimal("1000")
        )
      )
    end

    it "creates a Transaction for the paid amount only" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(Transaction).to have_received(:create!).with(
        hash_including(
          amount: BigDecimal("1000"),
          transaction_type: "income"
        )
      )
    end

    it "enqueues ReviewRequestJob for partial payment" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(ReviewRequestJob).to have_received(:perform_later).with(9)
    end
  end

  describe "Case 4: No payment received" do
    let(:pending_job) { instance_double(Job, id: 10, paid_amount: BigDecimal("0"), status: "pending", description: "Revisión eléctrica", payment_method: "pending", client: client) }

    let(:action_data) do
      {
        "client_name" => "Martínez",
        "client_phone" => "5212219876543",
        "description" => "Revisión eléctrica",
        "amount" => "800",
        "paid_amount" => "0",
        "payment_method" => "pending"
      }
    end

    before do
      allow(Job).to receive(:create!).and_return(pending_job)
    end

    it "creates a Job with status pending" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(Job).to have_received(:create!).with(
        hash_including(status: "pending", paid_amount: BigDecimal("0"))
      )
    end

    it "does not create a Transaction when paid_amount is zero" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(Transaction).not_to have_received(:create!)
    end

    it "does not enqueue ReviewRequestJob for pending jobs" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(ReviewRequestJob).not_to have_received(:perform_later)
    end
  end

  describe "Case 5: Material expense" do
    context "when expense is for a specific job" do
      let(:associated_job) { instance_double(Job, id: 8, client: client) }

      let(:action_data) do
        {
          "description" => "Cable calibre 12, 50 metros",
          "amount" => "350",
          "payment_method" => "cash",
          "job_id" => "8"
        }
      end

      before do
        allow(provider_jobs).to receive(:find_by).with(id: "8").and_return(associated_job)
      end

      it "creates an expense Transaction associated to the job" do
        described_class.call(provider: provider, action: "register_expense", action_data: action_data)

        expect(Transaction).to have_received(:create!).with(
          hash_including(
            provider: provider,
            job: associated_job,
            client: client,
            amount: BigDecimal("350"),
            transaction_type: "expense",
            description: "Cable calibre 12, 50 metros",
            assigned_to: "8"
          )
        )
      end
    end

    context "when expense is general (no specific job)" do
      let(:action_data) do
        {
          "description" => "Gasolina para la camioneta",
          "amount" => "500",
          "payment_method" => "cash",
          "job_id" => nil
        }
      end

      before do
        allow(provider_jobs).to receive(:find_by).with(id: nil).and_return(nil)
      end

      it "creates an expense Transaction with assigned_to general" do
        described_class.call(provider: provider, action: "register_expense", action_data: action_data)

        expect(Transaction).to have_received(:create!).with(
          hash_including(
            provider: provider,
            job: nil,
            client: nil,
            amount: BigDecimal("500"),
            transaction_type: "expense",
            assigned_to: "general"
          )
        )
      end
    end
  end

  describe "transaction_type safety" do
    let(:action_data) do
      {
        "client_name" => "Martínez",
        "client_phone" => "5212219876543",
        "description" => "Trabajo",
        "amount" => "1000",
        "paid_amount" => "1000",
        "payment_method" => "cash"
      }
    end

    it "always uses transaction_type: income for job payments" do
      described_class.call(provider: provider, action: "register_job", action_data: action_data)

      expect(Transaction).to have_received(:create!).with(
        hash_including(transaction_type: "income")
      )
    end

    it "always uses transaction_type: expense for material expenses" do
      expense_data = { "description" => "Material", "amount" => "200", "payment_method" => "cash", "job_id" => nil }
      allow(provider_jobs).to receive(:find_by).and_return(nil)

      described_class.call(provider: provider, action: "register_expense", action_data: expense_data)

      expect(Transaction).to have_received(:create!).with(
        hash_including(transaction_type: "expense")
      )
    end
  end
end
