# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::TaskService do
  let(:provider) { instance_double(Provider, id: 1, name: "Miguel García") }
  let(:tasks_relation) { double("tasks_relation") }

  before do
    allow(provider).to receive(:tasks).and_return(tasks_relation)
  end

  describe ".call" do
    context "when creating a task with full action_data" do
      let(:task) { instance_double(Task, id: 42, description: "Llamar al señor Pérez") }

      before do
        allow(tasks_relation).to receive(:create!).and_return(task)
        allow(Rails.logger).to receive(:info)
      end

      it "creates a task with the provided description" do
        action_data = {
          "description" => "Llamar al señor Pérez",
          "priority" => "normal",
          "snoozed_until" => nil
        }

        described_class.call(provider: provider, action_data: action_data)

        expect(tasks_relation).to have_received(:create!).with(
          description: "Llamar al señor Pérez",
          status: "pending",
          priority: "normal",
          snoozed_until: nil
        )
      end

      it "returns the created task" do
        action_data = { "description" => "Llamar al señor Pérez" }

        result = described_class.call(provider: provider, action_data: action_data)

        expect(result).to eq(task)
      end

      it "logs the task creation" do
        action_data = { "description" => "Llamar al señor Pérez" }

        described_class.call(provider: provider, action_data: action_data)

        expect(Rails.logger).to have_received(:info).with(
          a_string_including("[TaskService]", "Miguel García", "Llamar al señor Pérez")
        )
      end
    end

    context "when priority is provided" do
      let(:task) { instance_double(Task, id: 43, description: "Urgente") }

      before do
        allow(tasks_relation).to receive(:create!).and_return(task)
        allow(Rails.logger).to receive(:info)
      end

      %w[low normal urgent].each do |valid_priority|
        it "accepts '#{valid_priority}' as a valid priority" do
          described_class.call(provider: provider, action_data: { "description" => "Tarea", "priority" => valid_priority })

          expect(tasks_relation).to have_received(:create!).with(
            hash_including(priority: valid_priority)
          )
        end
      end

      it "defaults to 'normal' when priority is invalid" do
        described_class.call(provider: provider, action_data: { "description" => "Tarea", "priority" => "super_high" })

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(priority: "normal")
        )
      end

      it "defaults to 'normal' when priority is blank" do
        described_class.call(provider: provider, action_data: { "description" => "Tarea", "priority" => "" })

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(priority: "normal")
        )
      end

      it "defaults to 'normal' when priority is not provided" do
        described_class.call(provider: provider, action_data: { "description" => "Tarea" })

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(priority: "normal")
        )
      end
    end

    context "when snoozed_until is provided" do
      let(:task) { instance_double(Task, id: 44, description: "Comprar cable") }

      before do
        allow(tasks_relation).to receive(:create!).and_return(task)
        allow(Rails.logger).to receive(:info)
      end

      it "parses a valid ISO 8601 datetime" do
        action_data = {
          "description" => "Comprar cable",
          "snoozed_until" => "2025-04-20T09:00:00"
        }

        described_class.call(provider: provider, action_data: action_data)

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(snoozed_until: an_instance_of(ActiveSupport::TimeWithZone))
        )
      end

      it "sets snoozed_until to nil when value is blank" do
        action_data = { "description" => "Comprar cable", "snoozed_until" => "" }

        described_class.call(provider: provider, action_data: action_data)

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(snoozed_until: nil)
        )
      end

      it "sets snoozed_until to nil when value is nil" do
        action_data = { "description" => "Comprar cable", "snoozed_until" => nil }

        described_class.call(provider: provider, action_data: action_data)

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(snoozed_until: nil)
        )
      end

      it "sets snoozed_until to nil when value is unparseable" do
        action_data = { "description" => "Comprar cable", "snoozed_until" => "not-a-date" }

        described_class.call(provider: provider, action_data: action_data)

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(snoozed_until: nil)
        )
      end
    end

    context "when action_data is nil" do
      let(:task) { instance_double(Task, id: 45, description: nil) }

      before do
        allow(tasks_relation).to receive(:create!).and_return(task)
        allow(Rails.logger).to receive(:info)
      end

      it "handles nil action_data gracefully" do
        result = described_class.call(provider: provider, action_data: nil)

        expect(result).to eq(task)
        expect(tasks_relation).to have_received(:create!).with(
          description: nil,
          status: "pending",
          priority: "normal",
          snoozed_until: nil
        )
      end
    end

    context "when task always has status pending" do
      let(:task) { instance_double(Task, id: 46, description: "Tarea nueva") }

      before do
        allow(tasks_relation).to receive(:create!).and_return(task)
        allow(Rails.logger).to receive(:info)
      end

      it "always creates tasks with status pending" do
        described_class.call(provider: provider, action_data: { "description" => "Tarea nueva" })

        expect(tasks_relation).to have_received(:create!).with(
          hash_including(status: "pending")
        )
      end
    end
  end
end
