# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::AppointmentService do
  let(:provider) { instance_double(Provider, id: 1, phone: "5212211234567") }
  let(:client) { instance_double(Client, id: 42, name: "Mariana López") }
  let(:from) { "5212219876543" }
  let(:conversation) { instance_double(Conversation, context: {}) }
  let(:work_days_relation) { double("work_days_relation") }

  let(:action_data) do
    {
      "description" => "Revisión eléctrica",
      "address" => "Calle Independencia 45",
      "date" => Date.tomorrow.to_s,
      "time" => "10:00",
      "duration" => "90"
    }
  end

  let(:appointment) do
    instance_double(
      Appointment,
      id: 1,
      description: "Revisión eléctrica",
      address: "Calle Independencia 45",
      scheduled_at: Time.zone.parse("#{Date.tomorrow} 10:00"),
      estimated_duration: 90
    )
  end

  before do
    allow(provider).to receive(:work_days).and_return(work_days_relation)
    allow(work_days_relation).to receive(:find_by).and_return(nil)
    allow(Appointment).to receive(:create!).and_return(appointment)
    allow(WhatsAppService).to receive(:send_message).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_PROVIDER_PHONE_NUMBER_ID").and_return("1152919394565310")
  end

  describe ".call" do
    it "creates an appointment with correct attributes" do
      described_class.call(
        provider: provider, client: client, from: from,
        action_data: action_data, conversation: conversation
      )

      expect(Appointment).to have_received(:create!).with(
        hash_including(
          provider: provider,
          client: client,
          description: "Revisión eléctrica",
          address: "Calle Independencia 45",
          status: "pending",
          how_client_arrived: "whatsapp_direct",
          estimated_duration: 90
        )
      )
    end

    it "notifies provider with appointment summary" do
      described_class.call(
        provider: provider, client: client, from: from,
        action_data: action_data, conversation: conversation
      )

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: a_string_matching(/Nueva cita agendada/),
        phone_number_id: "1152919394565310"
      )
    end

    it "includes client name in notification" do
      described_class.call(
        provider: provider, client: client, from: from,
        action_data: action_data, conversation: conversation
      )

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: a_string_matching(/Mariana López/),
        phone_number_id: "1152919394565310"
      )
    end

    it "includes client phone in notification" do
      described_class.call(
        provider: provider, client: client, from: from,
        action_data: action_data, conversation: conversation
      )

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: a_string_matching(/5212219876543/),
        phone_number_id: "1152919394565310"
      )
    end

    it "returns the appointment" do
      result = described_class.call(
        provider: provider, client: client, from: from,
        action_data: action_data, conversation: conversation
      )

      expect(result).to eq(appointment)
    end

    context "when client is nil" do
      it "returns nil without creating an appointment" do
        result = described_class.call(
          provider: provider, client: nil, from: from,
          action_data: action_data, conversation: conversation
        )

        expect(result).to be_nil
        expect(Appointment).not_to have_received(:create!)
      end
    end

    context "when date is missing" do
      let(:action_data) { { "description" => "Revisión", "time" => "10:00" } }

      it "defaults to today" do
        described_class.call(
          provider: provider, client: client, from: from,
          action_data: action_data, conversation: conversation
        )

        expect(Appointment).to have_received(:create!).with(
          hash_including(scheduled_at: Time.zone.parse("#{Date.current} 10:00"))
        )
      end
    end

    context "when duration is missing" do
      let(:action_data) { { "description" => "Revisión", "date" => Date.tomorrow.to_s } }

      it "defaults to 60 minutes" do
        described_class.call(
          provider: provider, client: client, from: from,
          action_data: action_data, conversation: conversation
        )

        expect(Appointment).to have_received(:create!).with(
          hash_including(estimated_duration: 60)
        )
      end
    end

    context "when description comes from conversation context" do
      let(:action_data) { { "date" => Date.tomorrow.to_s } }
      let(:conversation) { instance_double(Conversation, context: { "service_requested" => "Fuga en cocina" }) }

      it "uses service_requested from context" do
        described_class.call(
          provider: provider, client: client, from: from,
          action_data: action_data, conversation: conversation
        )

        expect(Appointment).to have_received(:create!).with(
          hash_including(description: "Fuga en cocina")
        )
      end
    end
  end
end
