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
    allow(WhatsAppService).to receive(:send_message)
  end

  describe "#perform" do
    context "when appointment is not found" do
      it "returns silently without sending any message" do
        allow(Appointment).to receive(:find_by).with(id: 999).and_return(nil)

        expect(WhatsAppService).not_to receive(:send_message)

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
        expect(WhatsAppService).not_to receive(:send_message)

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
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 3).and_return(appointment_no_phone)
      end

      it "skips without sending any message" do
        expect(WhatsAppService).not_to receive(:send_message)

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
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 4).and_return(appointment_blank_phone)
      end

      it "skips without sending any message" do
        expect(WhatsAppService).not_to receive(:send_message)

        described_class.new.perform(4)
      end
    end

    context "when all conditions are met for sending" do
      it "sends a reminder message via WhatsAppService" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_including("Mariana López", "Miguel García")
        )

        described_class.new.perform(1)
      end

      it "includes the service description" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_including("Revisión de instalación eléctrica")
        )

        described_class.new.perform(1)
      end

      it "includes the scheduled time" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_including("15/05/2025 a las 10:00")
        )

        described_class.new.perform(1)
      end

      it "includes the address" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_including("Calle Independencia 45, Boca del Río")
        )

        described_class.new.perform(1)
      end

      it "includes the provider name" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_including("Miguel García")
        )

        described_class.new.perform(1)
      end
    end

    context "when appointment has no address" do
      let(:appointment_no_address) do
        instance_double(
          Appointment,
          id: 5,
          status: "pending",
          scheduled_at: scheduled_time,
          description: "Reparación de fuga",
          address: nil,
          client: client,
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 5).and_return(appointment_no_address)
      end

      it "sends the reminder without an address line" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_including("Miguel García", "Reparación de fuga")
        )

        described_class.new.perform(5)
      end

      it "does not include the address marker" do
        expect(WhatsAppService).to receive(:send_message) do |args|
          expect(args[:message]).not_to include("📍")
        end

        described_class.new.perform(5)
      end
    end

    context "when appointment has no description" do
      let(:appointment_no_description) do
        instance_double(
          Appointment,
          id: 6,
          status: "confirmed",
          scheduled_at: scheduled_time,
          description: nil,
          address: "Av. Reforma 100",
          client: client,
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 6).and_return(appointment_no_description)
      end

      it "uses a fallback description" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_including("tu servicio")
        )

        described_class.new.perform(6)
      end
    end

    context "when client has no name" do
      let(:client_no_name) { instance_double(Client, name: nil, phone: "5212219876543") }
      let(:appointment_no_client_name) do
        instance_double(
          Appointment,
          id: 7,
          status: "confirmed",
          scheduled_at: scheduled_time,
          description: "Instalación eléctrica",
          address: "Centro, Veracruz",
          client: client_no_name,
          provider: provider
        )
      end

      before do
        allow(Appointment).to receive(:find_by).with(id: 7).and_return(appointment_no_client_name)
      end

      it "sends a generic greeting without the client name" do
        expect(WhatsAppService).to receive(:send_message).with(
          to: "5212219876543",
          message: a_string_starting_with("Hola 👋")
        )

        described_class.new.perform(7)
      end
    end
  end

  describe "message tone and format" do
    it "uses no more than 2 emojis" do
      expect(WhatsAppService).to receive(:send_message) do |args|
        emoji_count = args[:message].scan(/[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/).size
        expect(emoji_count).to be <= 2
      end

      described_class.new.perform(1)
    end

    it "keeps the message within 5-6 lines" do
      expect(WhatsAppService).to receive(:send_message) do |args|
        line_count = args[:message].split("\n").size
        expect(line_count).to be <= 6
      end

      described_class.new.perform(1)
    end
  end
end
