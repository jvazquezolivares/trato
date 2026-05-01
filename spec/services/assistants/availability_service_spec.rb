# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::AvailabilityService do
  let(:provider) { instance_double(Provider, id: 1) }
  let(:work_days_relation) { double("work_days_relation") }

  before do
    allow(provider).to receive(:work_days).and_return(work_days_relation)
  end

  describe ".call" do
    context "when provider has no work day for the date" do
      before do
        allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(nil)
      end

      it "returns no availability message" do
        result = described_class.call(provider: provider)

        expect(result).to eq("No ha reportado disponibilidad hoy")
      end
    end

    context "when provider has an active work day" do
      let(:work_day) do
        instance_double(WorkDay, status: "active", starts_at: Time.zone.parse("08:00"), ends_at: Time.zone.parse("18:00"))
      end

      before do
        allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(work_day)
      end

      it "returns availability with time range" do
        result = described_class.call(provider: provider)

        expect(result).to eq("Disponible hoy de 08:00 a 18:00")
      end
    end

    context "when provider has finished their day" do
      let(:work_day) do
        instance_double(WorkDay, status: "finished", starts_at: Time.zone.parse("08:00"), ends_at: Time.zone.parse("15:00"))
      end

      before do
        allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(work_day)
      end

      it "returns finished message" do
        result = described_class.call(provider: provider)

        expect(result).to eq("Ya terminó su jornada hoy")
      end
    end

    context "when provider is planning" do
      let(:work_day) do
        instance_double(WorkDay, status: "planning", starts_at: Time.zone.parse("09:00"), ends_at: Time.zone.parse("17:00"))
      end

      before do
        allow(work_days_relation).to receive(:find_by).with(date: Date.current).and_return(work_day)
      end

      it "returns planning message with time range" do
        result = described_class.call(provider: provider)

        expect(result).to eq("Planificando su día (09:00 a 17:00)")
      end
    end

    context "when a specific date is provided" do
      let(:target_date) { Date.tomorrow }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: target_date).and_return(nil)
      end

      it "queries for the specified date" do
        described_class.call(provider: provider, date: target_date)

        expect(work_days_relation).to have_received(:find_by).with(date: target_date)
      end
    end
  end
end
