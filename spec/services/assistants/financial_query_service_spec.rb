# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::FinancialQueryService do
  let(:provider) { instance_double(Provider, id: 1) }
  let(:transactions_relation) { double("transactions_relation") }
  let(:jobs_relation) { double("jobs_relation") }

  before do
    allow(provider).to receive(:transactions).and_return(transactions_relation)
    allow(provider).to receive(:jobs).and_return(jobs_relation)
  end

  describe ".call" do
    context "when query_type is invalid" do
      it "returns an error hash" do
        result = described_class.call(provider: provider, query_type: "invalid")

        expect(result).to eq("error" => "Tipo de consulta no reconocido")
      end
    end

    context "when date range is missing for a query that requires it" do
      it "returns an error for earnings without dates" do
        result = described_class.call(provider: provider, query_type: "earnings")

        expect(result).to eq("error" => "Se requiere rango de fechas para esta consulta")
      end

      it "returns an error for expenses without dates" do
        result = described_class.call(provider: provider, query_type: "expenses")

        expect(result).to eq("error" => "Se requiere rango de fechas para esta consulta")
      end

      it "returns an error for summary without dates" do
        result = described_class.call(provider: provider, query_type: "summary")

        expect(result).to eq("error" => "Se requiere rango de fechas para esta consulta")
      end
    end

    context "when outstanding is queried without dates" do
      let(:outstanding_scope) { double("outstanding_scope") }
      let(:outstanding_ordered) { double("outstanding_ordered") }

      before do
        allow(jobs_relation).to receive(:includes).with(:client).and_return(outstanding_scope)
        allow(outstanding_scope).to receive(:where).with(status: %w[pending partial]).and_return(outstanding_ordered)
        allow(outstanding_ordered).to receive(:order).with(service_date: :desc).and_return([])
      end

      it "does not require dates" do
        result = described_class.call(provider: provider, query_type: "outstanding")

        expect(result["query_type"]).to eq("outstanding")
        expect(result).not_to have_key("error")
      end
    end
  end

  describe "earnings" do
    let(:income_scope) { double("income_scope") }
    let(:income_filtered) { double("income_filtered") }
    let(:income_distinct) { double("income_distinct") }

    before do
      allow(transactions_relation).to receive(:where).with(transaction_type: "income").and_return(income_scope)
      allow(income_scope).to receive(:where).with(recorded_at: anything).and_return(income_filtered)
      allow(income_filtered).to receive(:sum).with(:amount).and_return(BigDecimal("5500"))
      allow(income_filtered).to receive(:distinct).and_return(income_distinct)
      allow(income_distinct).to receive(:count).with(:job_id).and_return(3)
    end

    it "returns income for the given date range" do
      result = described_class.call(
        provider: provider, query_type: "earnings",
        date_from: "2026-04-27", date_to: "2026-05-01"
      )

      expect(result["income"]).to eq(5500.0)
    end

    it "returns the job count" do
      result = described_class.call(
        provider: provider, query_type: "earnings",
        date_from: "2026-04-27", date_to: "2026-05-01"
      )

      expect(result["job_count"]).to eq(3)
    end

    it "includes the date range in the response" do
      result = described_class.call(
        provider: provider, query_type: "earnings",
        date_from: "2026-04-27", date_to: "2026-05-01"
      )

      expect(result["date_from"]).to eq("2026-04-27")
      expect(result["date_to"]).to eq("2026-05-01")
    end

    it "accepts Date objects as date parameters" do
      result = described_class.call(
        provider: provider, query_type: "earnings",
        date_from: Date.new(2026, 4, 27), date_to: Date.new(2026, 5, 1)
      )

      expect(result["income"]).to eq(5500.0)
    end
  end

  describe "expenses" do
    let(:expense_scope) { double("expense_scope") }
    let(:expense_filtered) { double("expense_filtered") }
    let(:expense_ordered) { double("expense_ordered") }
    let(:expense_limited) { double("expense_limited") }
    let(:recorded_time) { Time.zone.parse("2026-04-28 10:00:00") }

    before do
      allow(transactions_relation).to receive(:where).with(transaction_type: "expense").and_return(expense_scope)
      allow(expense_scope).to receive(:where).with(recorded_at: anything).and_return(expense_filtered)
      allow(expense_filtered).to receive(:sum).with(:amount).and_return(BigDecimal("1200"))
      allow(expense_filtered).to receive(:order).with(recorded_at: :desc).and_return(expense_ordered)
      allow(expense_ordered).to receive(:limit).with(10).and_return(expense_limited)
      allow(expense_limited).to receive(:pluck)
        .with(:description, :amount, :recorded_at)
        .and_return([
          ["Cable calibre 12", BigDecimal("350"), recorded_time],
          ["Tubo PVC", BigDecimal("850"), recorded_time]
        ])
    end

    it "returns total expenses for the date range" do
      result = described_class.call(
        provider: provider, query_type: "expenses",
        date_from: "2026-04-27", date_to: "2026-05-01"
      )

      expect(result["total_expenses"]).to eq(1200.0)
    end

    it "returns itemized expense details" do
      result = described_class.call(
        provider: provider, query_type: "expenses",
        date_from: "2026-04-27", date_to: "2026-05-01"
      )

      descriptions = result["expenses"].map { |e| e["description"] }
      expect(descriptions).to contain_exactly("Cable calibre 12", "Tubo PVC")
    end

    it "returns the expense count" do
      result = described_class.call(
        provider: provider, query_type: "expenses",
        date_from: "2026-04-27", date_to: "2026-05-01"
      )

      expect(result["expense_count"]).to eq(2)
    end
  end

  describe "outstanding" do
    let(:client_martinez) { instance_double(Client, name: "Martínez", phone: "5212219876543") }
    let(:client_lopez) { instance_double(Client, name: "López", phone: "5212219876544") }

    let(:job_partial) do
      instance_double(Job,
        description: "Fuga en cocina",
        amount: BigDecimal("2500"), paid_amount: BigDecimal("1500"),
        status: "partial", service_date: Date.new(2026, 4, 15),
        client: client_martinez)
    end

    let(:job_pending) do
      instance_double(Job,
        description: "Instalación eléctrica",
        amount: BigDecimal("4000"), paid_amount: BigDecimal("0"),
        status: "pending", service_date: Date.new(2026, 4, 20),
        client: client_lopez)
    end

    let(:outstanding_scope) { double("outstanding_scope") }
    let(:outstanding_ordered) { double("outstanding_ordered") }

    before do
      allow(jobs_relation).to receive(:includes).with(:client).and_return(outstanding_scope)
      allow(outstanding_scope).to receive(:where).with(status: %w[pending partial]).and_return(outstanding_ordered)
      allow(outstanding_ordered).to receive(:order).with(service_date: :desc).and_return([job_partial, job_pending])
    end

    it "returns total outstanding amount" do
      result = described_class.call(provider: provider, query_type: "outstanding")

      expect(result["total_outstanding"]).to eq(5000.0)
    end

    it "groups by client" do
      result = described_class.call(provider: provider, query_type: "outstanding")

      client_names = result["clients"].map { |c| c["client_name"] }
      expect(client_names).to contain_exactly("Martínez", "López")
    end

    it "calculates per-client outstanding correctly" do
      result = described_class.call(provider: provider, query_type: "outstanding")

      martinez = result["clients"].find { |c| c["client_name"] == "Martínez" }
      expect(martinez["total_owed"]).to eq(1000.0)
    end

    it "includes job details per client" do
      result = described_class.call(provider: provider, query_type: "outstanding")

      lopez = result["clients"].find { |c| c["client_name"] == "López" }
      expect(lopez["jobs"].first["outstanding"]).to eq(4000.0)
    end

    it "does not require date parameters" do
      result = described_class.call(provider: provider, query_type: "outstanding")

      expect(result).not_to have_key("date_from")
      expect(result).not_to have_key("date_to")
    end
  end

  describe "summary" do
    let(:income_scope) { double("income_scope") }
    let(:expense_scope) { double("expense_scope") }
    let(:income_filtered) { double("income_filtered") }
    let(:expense_filtered) { double("expense_filtered") }
    let(:jobs_date_scope) { double("jobs_date_scope") }
    let(:jobs_outstanding_scope) { double("jobs_outstanding_scope") }

    before do
      allow(transactions_relation).to receive(:where).with(transaction_type: "income").and_return(income_scope)
      allow(transactions_relation).to receive(:where).with(transaction_type: "expense").and_return(expense_scope)
      allow(income_scope).to receive(:where).with(recorded_at: anything).and_return(income_filtered)
      allow(expense_scope).to receive(:where).with(recorded_at: anything).and_return(expense_filtered)
      allow(income_filtered).to receive(:sum).with(:amount).and_return(BigDecimal("15000"))
      allow(expense_filtered).to receive(:sum).with(:amount).and_return(BigDecimal("3000"))

      allow(jobs_relation).to receive(:where).with(service_date: anything).and_return(jobs_date_scope)
      allow(jobs_date_scope).to receive(:count).and_return(8)

      allow(jobs_relation).to receive(:where).with(status: %w[pending partial]).and_return(jobs_outstanding_scope)
      allow(jobs_outstanding_scope).to receive(:sum).with("amount - paid_amount").and_return(BigDecimal("5000"))
    end

    it "returns income for the period" do
      result = described_class.call(
        provider: provider, query_type: "summary",
        date_from: "2026-04-01", date_to: "2026-04-30"
      )

      expect(result["income"]).to eq(15_000.0)
    end

    it "returns expenses for the period" do
      result = described_class.call(
        provider: provider, query_type: "summary",
        date_from: "2026-04-01", date_to: "2026-04-30"
      )

      expect(result["expenses"]).to eq(3000.0)
    end

    it "returns net (income - expenses)" do
      result = described_class.call(
        provider: provider, query_type: "summary",
        date_from: "2026-04-01", date_to: "2026-04-30"
      )

      expect(result["net"]).to eq(12_000.0)
    end

    it "returns outstanding collections" do
      result = described_class.call(
        provider: provider, query_type: "summary",
        date_from: "2026-04-01", date_to: "2026-04-30"
      )

      expect(result["outstanding_collections"]).to eq(5000.0)
    end

    it "returns job count for the period" do
      result = described_class.call(
        provider: provider, query_type: "summary",
        date_from: "2026-04-01", date_to: "2026-04-30"
      )

      expect(result["job_count"]).to eq(8)
    end
  end

  describe "date parsing" do
    let(:income_scope) { double("income_scope") }
    let(:income_filtered) { double("income_filtered") }
    let(:income_distinct) { double("income_distinct") }

    before do
      allow(transactions_relation).to receive(:where).with(transaction_type: "income").and_return(income_scope)
      allow(income_scope).to receive(:where).with(recorded_at: anything).and_return(income_filtered)
      allow(income_filtered).to receive(:sum).with(:amount).and_return(BigDecimal("0"))
      allow(income_filtered).to receive(:distinct).and_return(income_distinct)
      allow(income_distinct).to receive(:count).with(:job_id).and_return(0)
    end

    it "handles invalid date strings gracefully" do
      result = described_class.call(
        provider: provider, query_type: "earnings",
        date_from: "not-a-date", date_to: "2026-05-01"
      )

      expect(result).to eq("error" => "Se requiere rango de fechas para esta consulta")
    end

    it "handles nil dates gracefully" do
      result = described_class.call(
        provider: provider, query_type: "earnings",
        date_from: nil, date_to: nil
      )

      expect(result).to eq("error" => "Se requiere rango de fechas para esta consulta")
    end
  end
end
