# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::WorkDayService do
  let(:provider) { instance_double(Provider, id: 1) }
  let(:work_days_relation) { double("work_days_relation") }

  before do
    allow(provider).to receive(:work_days).and_return(work_days_relation)
  end

  describe ".call" do
    context "when no WorkDay exists for today" do
      let(:work_day) { instance_double(WorkDay, new_record?: true, persisted?: false) }

      before do
        allow(work_days_relation).to receive(:find_or_initialize_by)
          .with(date: Date.current)
          .and_return(work_day)
        allow(work_day).to receive(:starts_at=)
        allow(work_day).to receive(:ends_at=)
        allow(work_day).to receive(:status=)
        allow(work_day).to receive(:notes=)
        allow(work_day).to receive(:save!).and_return(true)
      end

      it "creates a new WorkDay for today" do
        action_data = {
          "starts_at" => "08:00",
          "ends_at" => "18:00",
          "status" => "active",
          "notes" => "Tengo cita en Boca del Río a las 10"
        }

        result = described_class.call(provider: provider, action_data: action_data)

        expect(result).to eq(work_day)
        expect(work_day).to have_received(:starts_at=).with("08:00")
        expect(work_day).to have_received(:ends_at=).with("18:00")
        expect(work_day).to have_received(:status=).with("active")
        expect(work_day).to have_received(:notes=).with("Tengo cita en Boca del Río a las 10")
        expect(work_day).to have_received(:save!)
      end

      it "normalizes single-digit hours" do
        action_data = { "starts_at" => "8:00", "ends_at" => "6:30", "status" => "active" }

        described_class.call(provider: provider, action_data: action_data)

        expect(work_day).to have_received(:starts_at=).with("08:00")
        expect(work_day).to have_received(:ends_at=).with("06:30")
      end

      it "defaults status to active when not provided" do
        action_data = { "starts_at" => "09:00" }

        described_class.call(provider: provider, action_data: action_data)

        expect(work_day).to have_received(:status=).with("active")
      end

      it "defaults status to active when invalid status provided" do
        action_data = { "status" => "invalid_status" }

        described_class.call(provider: provider, action_data: action_data)

        expect(work_day).to have_received(:status=).with("active")
      end
    end

    context "when a WorkDay already exists for today" do
      let(:existing_work_day) do
        instance_double(WorkDay, new_record?: false, persisted?: true)
      end

      before do
        allow(work_days_relation).to receive(:find_or_initialize_by)
          .with(date: Date.current)
          .and_return(existing_work_day)
        allow(existing_work_day).to receive(:starts_at=)
        allow(existing_work_day).to receive(:ends_at=)
        allow(existing_work_day).to receive(:status=)
        allow(existing_work_day).to receive(:notes=)
        allow(existing_work_day).to receive(:save!).and_return(true)
      end

      it "updates the existing WorkDay" do
        action_data = { "ends_at" => "17:00", "status" => "finished" }

        result = described_class.call(provider: provider, action_data: action_data)

        expect(result).to eq(existing_work_day)
        expect(existing_work_day).to have_received(:ends_at=).with("17:00")
        expect(existing_work_day).to have_received(:status=).with("finished")
        expect(existing_work_day).to have_received(:save!)
      end

      it "only updates provided fields" do
        action_data = { "status" => "finished" }

        described_class.call(provider: provider, action_data: action_data)

        expect(existing_work_day).not_to have_received(:starts_at=)
        expect(existing_work_day).not_to have_received(:ends_at=)
        expect(existing_work_day).to have_received(:status=).with("finished")
      end
    end

    context "when action_data is nil" do
      let(:work_day) { instance_double(WorkDay, new_record?: true) }

      before do
        allow(work_days_relation).to receive(:find_or_initialize_by)
          .with(date: Date.current)
          .and_return(work_day)
        allow(work_day).to receive(:status=)
        allow(work_day).to receive(:save!).and_return(true)
      end

      it "handles nil action_data gracefully" do
        result = described_class.call(provider: provider, action_data: nil)

        expect(result).to eq(work_day)
        expect(work_day).to have_received(:status=).with("active")
        expect(work_day).to have_received(:save!)
      end
    end

    context "with valid status values" do
      let(:work_day) { instance_double(WorkDay, new_record?: true) }

      before do
        allow(work_days_relation).to receive(:find_or_initialize_by)
          .with(date: Date.current)
          .and_return(work_day)
        allow(work_day).to receive(:starts_at=)
        allow(work_day).to receive(:ends_at=)
        allow(work_day).to receive(:status=)
        allow(work_day).to receive(:notes=)
        allow(work_day).to receive(:save!).and_return(true)
      end

      %w[planning active finished].each do |valid_status|
        it "accepts '#{valid_status}' as a valid status" do
          described_class.call(provider: provider, action_data: { "status" => valid_status })

          expect(work_day).to have_received(:status=).with(valid_status)
        end
      end
    end
  end
end
