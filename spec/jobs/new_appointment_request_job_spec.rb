# frozen_string_literal: true

require "rails_helper"

RSpec.describe NewAppointmentRequestJob, type: :job do
  let(:provider) { instance_double(Provider, name: "Miguel García", phone: "5212211234567") }
  let(:client) { instance_double(Client, name: "Mariana López", phone: "5212219876543") }
  let(:scheduled_at) { Time.zone.local(2025, 6, 15, 14, 30) }
  let(:appointment) do
    instance_double(
      Appointment,
      id: 42,
      status: "pending",
      provider: provider,
      client: client,
      description: "Reparación de lavadora",
      scheduled_at: scheduled_at
    )
  end

  before do
    allow(Appointment).to receive(:find_by).with(id: 42).and_return(appointment)
    allow(WhatsAppService).to receive(:send_template_message)
  end

  describe "#perform" do
    context "when appointment is not found" do
      it "returns silently without sending any message" do
        allow(Appointment).to receive(:find_by).with(id: 999).and_return(nil)

        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform(999)
      end
    end

    context "when appointment is cancelled" do
      let(:cancelled_appointment) do
        instance_double(
          Appointment,
          id: 43,
          status: "cancelled",
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 43).and_return(cancelled_appointment)
      end

      it "skips without error" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform(43)
      end
    end

    context "when provider has no phone on record" do
      let(:provider_no_phone) { instance_double(Provider, name: "Sin Teléfono", phone: nil) }
      let(:appointment_no_phone) do
        instance_double(
          Appointment,
          id: 44,
          status: "pending",
          provider: provider_no_phone,
          client: client,
          description: "Servicio",
          scheduled_at: scheduled_at
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 44).and_return(appointment_no_phone)
      end

      it "skips without error" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform(44)
      end
    end

    context "when provider has blank phone" do
      let(:provider_blank_phone) { instance_double(Provider, name: "Blank", phone: "") }
      let(:appointment_blank_phone) do
        instance_double(
          Appointment,
          id: 45,
          status: "pending",
          provider: provider_blank_phone,
          client: client,
          description: "Servicio",
          scheduled_at: scheduled_at
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 45).and_return(appointment_blank_phone)
      end

      it "skips without error" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform(45)
      end
    end

    context "when all conditions are met for sending" do
      it "sends new appointment request template via WhatsAppService" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "new_appointment_request",
          parameters: ["Mariana López", "Reparación de lavadora", "15/06/2025", "14:30"],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform(42)
      end
    end

    context "when client has no name" do
      let(:client_no_name) { instance_double(Client, name: nil, phone: "5212219876543") }
      let(:appointment_no_name) do
        instance_double(
          Appointment,
          id: 46,
          status: "pending",
          provider: provider,
          client: client_no_name,
          description: "Servicio",
          scheduled_at: scheduled_at
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 46).and_return(appointment_no_name)
      end

      it "uses 'Un cliente' as default client name" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "new_appointment_request",
          parameters: ["Un cliente", "Servicio", "15/06/2025", "14:30"],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform(46)
      end
    end

    context "when appointment has no description" do
      let(:appointment_no_description) do
        instance_double(
          Appointment,
          id: 47,
          status: "pending",
          provider: provider,
          client: client,
          description: nil,
          scheduled_at: scheduled_at
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 47).and_return(appointment_no_description)
      end

      it "uses 'servicio solicitado' as default description" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "new_appointment_request",
          parameters: ["Mariana López", "servicio solicitado", "15/06/2025", "14:30"],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform(47)
      end
    end

    context "when appointment has no scheduled_at" do
      let(:appointment_no_date) do
        instance_double(
          Appointment,
          id: 48,
          status: "pending",
          provider: provider,
          client: client,
          description: "Servicio",
          scheduled_at: nil
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 48).and_return(appointment_no_date)
      end

      it "uses default placeholders for date and time" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "new_appointment_request",
          parameters: ["Mariana López", "Servicio", "próximamente", "por confirmar"],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform(48)
      end
    end
  end
end
