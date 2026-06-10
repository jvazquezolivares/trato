# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppointmentReminderJob, type: :job do
  let(:provider) { instance_double(Provider, name: "Miguel García", phone: "5212211234567") }
  let(:client) { instance_double(Client, name: "Mariana López", phone: "5212219876543") }
  let(:scheduled_time) { Time.zone.local(2025, 5, 15, 10, 0, 0) }
  let(:appointment) do
    instance_double(
      Appointment,
      id: 1,
      status: "confirmed",
      scheduled_at: scheduled_time,
      description: "Revisión de instalación eléctrica",
      address: "Calle Independencia 45, Boca del Río",
      client: client,
      provider: provider
    )
  end

  before do
    allow(Appointment).to receive(:find_by).with(id: 1).and_return(appointment)
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
          id: 2,
          status: "cancelled",
          client: client,
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 2).and_return(cancelled_appointment)
      end

      it "skips without sending any message" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform(2)
      end
    end

    context "when client has no phone" do
      let(:client_no_phone) { instance_double(Client, name: "Sin Teléfono", phone: nil) }
      let(:appointment_no_phone) do
        instance_double(
          Appointment,
          id: 3,
          status: "confirmed",
          client: client_no_phone,
          provider: provider,
          scheduled_at: scheduled_time,
          description: "Servicio",
          address: "Dirección"
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 3).and_return(appointment_no_phone)
      end

      it "skips without error" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform(3)
      end
    end

    context "when client has blank phone" do
      let(:client_blank_phone) { instance_double(Client, name: "Blank", phone: "") }
      let(:appointment_blank_phone) do
        instance_double(
          Appointment,
          id: 4,
          status: "confirmed",
          client: client_blank_phone,
          provider: provider,
          scheduled_at: scheduled_time,
          description: "Servicio",
          address: "Dirección"
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 4).and_return(appointment_blank_phone)
      end

      it "skips without error" do
        expect(WhatsAppService).not_to receive(:send_template_message)

        described_class.new.perform(4)
      end
    end

    context "when all conditions are met for sending" do
      it "sends appointment reminder template to client" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212219876543",
          template_name: "appointment_reminder",
          parameters: [
            "Mariana López",
            "Miguel García",
            "15/05/2025 a las 10:00",
            "Calle Independencia 45, Boca del Río"
          ],
          phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
        )

        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "appointment_reminder",
          parameters: [
            "Miguel García",
            "Mariana López",
            "15/05/2025 a las 10:00",
            "Calle Independencia 45, Boca del Río"
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform(1)
      end
    end

    context "when appointment has no address" do
      let(:appointment_no_address) do
        instance_double(
          Appointment,
          id: 5,
          status: "confirmed",
          scheduled_at: scheduled_time,
          description: "Servicio",
          address: nil,
          client: client,
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 5).and_return(appointment_no_address)
      end

      it "uses default location placeholder" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212219876543",
          template_name: "appointment_reminder",
          parameters: [
            "Mariana López",
            "Miguel García",
            "15/05/2025 a las 10:00",
            "ubicación por confirmar"
          ],
          phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
        )

        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "appointment_reminder",
          parameters: [
            "Miguel García",
            "Mariana López",
            "15/05/2025 a las 10:00",
            "ubicación por confirmar"
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform(5)
      end
    end

    context "when client has no name" do
      let(:client_no_name) { instance_double(Client, name: nil, phone: "5212219876543") }
      let(:appointment_no_name) do
        instance_double(
          Appointment,
          id: 6,
          status: "confirmed",
          scheduled_at: scheduled_time,
          description: "Servicio",
          address: "Dirección",
          client: client_no_name,
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 6).and_return(appointment_no_name)
      end

      it "uses 'Cliente' as default name for client" do
        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212219876543",
          template_name: "appointment_reminder",
          parameters: [
            "Cliente",
            "Miguel García",
            "15/05/2025 a las 10:00",
            "Dirección"
          ],
          phone_number_id: ENV["WHATSAPP_CLIENT_PHONE_NUMBER_ID"]
        )

        expect(WhatsAppService).to receive(:send_template_message).with(
          to: "5212211234567",
          template_name: "appointment_reminder",
          parameters: [
            "Miguel García",
            "Cliente",
            "15/05/2025 a las 10:00",
            "Dirección"
          ],
          phone_number_id: ENV["WHATSAPP_PROVIDER_PHONE_NUMBER_ID"]
        )

        described_class.new.perform(6)
      end
    end
  end
end
