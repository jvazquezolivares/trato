# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReviewRequestJob, type: :job do
  let(:provider) { instance_double(Provider, name: "Miguel García", phone: "5212211234567") }
  let(:client) { instance_double(Client, name: "Mariana López", phone: "5212219876543") }
  let(:job_record) do
    instance_double(
      Job,
      id: 42,
      review_sent?: false,
      review_attempts: 0,
      client: client,
      provider: provider
    )
  end

  before do
    allow(Job).to receive(:find_by).with(id: 42).and_return(job_record)
    allow(WhatsAppService).to receive(:send_list_message)
    allow(job_record).to receive(:update!)
  end

  describe "#perform" do
    context "when job is not found" do
      it "returns silently without sending any message" do
        allow(Job).to receive(:find_by).with(id: 999).and_return(nil)

        expect(WhatsAppService).not_to receive(:send_list_message)

        described_class.new.perform(999)
      end
    end

    context "when client has no phone on record" do
      let(:client_without_phone) { instance_double(Client, name: "Sin Teléfono", phone: nil) }
      let(:job_no_phone) do
        instance_double(
          Job,
          id: 43,
          review_sent?: false,
          review_attempts: 0,
          client: client_without_phone,
          provider: provider
        )
      end

      before do
        allow(Job).to receive(:find_by).with(id: 43).and_return(job_no_phone)
      end

      it "skips without error" do
        expect(WhatsAppService).not_to receive(:send_list_message)
        expect(job_no_phone).not_to receive(:update!)

        described_class.new.perform(43)
      end
    end

    context "when client has blank phone" do
      let(:client_blank_phone) { instance_double(Client, name: "Blank", phone: "") }
      let(:job_blank_phone) do
        instance_double(
          Job,
          id: 44,
          review_sent?: false,
          review_attempts: 0,
          client: client_blank_phone,
          provider: provider
        )
      end

      before do
        allow(Job).to receive(:find_by).with(id: 44).and_return(job_blank_phone)
      end

      it "skips without error" do
        expect(WhatsAppService).not_to receive(:send_list_message)
        expect(job_blank_phone).not_to receive(:update!)

        described_class.new.perform(44)
      end
    end

    context "when review already sent" do
      let(:job_already_sent) do
        instance_double(
          Job,
          id: 45,
          review_sent?: true,
          client: client,
          provider: provider
        )
      end

      before do
        allow(Job).to receive(:find_by).with(id: 45).and_return(job_already_sent)
      end

      it "skips without sending a message" do
        expect(WhatsAppService).not_to receive(:send_list_message)

        described_class.new.perform(45)
      end
    end

    context "when max attempts (3) reached" do
      let(:job_max_attempts) do
        instance_double(
          Job,
          id: 46,
          review_sent?: false,
          review_attempts: 3,
          client: client,
          provider: provider
        )
      end

      before do
        allow(Job).to receive(:find_by).with(id: 46).and_return(job_max_attempts)
      end

      it "stops and does not send further messages" do
        expect(WhatsAppService).not_to receive(:send_list_message)
        expect(job_max_attempts).not_to receive(:update!)

        described_class.new.perform(46)
      end
    end

    context "when all conditions are met for sending" do
      before do
        # Prevent rescheduling side effects in these tests
        allow(ReviewRequestJob).to receive_message_chain(:set, :perform_later)
        allow(WhatsAppService).to receive(:send_list_message)
      end

      it "sends review request List Message via WhatsAppService" do
        expect(WhatsAppService).to receive(:send_list_message).with(
          to: "5212219876543",
          payload: a_hash_including(
            type: "list",
            header: a_hash_including(text: "¿Cómo calificarías el trabajo?")
          )
        )

        described_class.new.perform(42)
      end

      it "sends List Message with 5 star rating options" do
        expect(WhatsAppService).to receive(:send_list_message) do |args|
          payload = args[:payload]
          rows = payload[:action][:sections].first[:rows]

          expect(rows.size).to eq(5)
          expect(rows.map { |r| r[:id] }).to eq(%w[5 4 3 2 1])
        end

        described_class.new.perform(42)
      end

      it "increments review_attempts and sets review_requested_at" do
        now = Time.current
        allow(Time).to receive(:current).and_return(now)

        expect(job_record).to receive(:update!).with(
          review_attempts: 1,
          review_requested_at: now
        )

        described_class.new.perform(42)
      end
    end

    context "when rescheduling after a successful attempt" do
      before do
        allow(job_record).to receive(:review_attempts).and_return(0, 1)
      end

      it "reschedules for the next 11am CDMX delivery when under max attempts" do
        job_with_scheduling = instance_double("ActiveJob::ConfiguredJob")
        allow(ReviewRequestJob).to receive(:set).and_return(job_with_scheduling)
        allow(job_with_scheduling).to receive(:perform_later)

        described_class.new.perform(42)

        expect(ReviewRequestJob).to have_received(:set).with(
          wait_until: an_instance_of(ActiveSupport::TimeWithZone)
        )
        expect(job_with_scheduling).to have_received(:perform_later).with(42)
      end
    end

    context "when at max attempts after incrementing" do
      let(:job_at_limit) do
        instance_double(
          Job,
          id: 47,
          review_sent?: false,
          review_attempts: 2,
          client: client,
          provider: provider
        )
      end

      before do
        allow(Job).to receive(:find_by).with(id: 47).and_return(job_at_limit)
        allow(job_at_limit).to receive(:update!)
        # After update!, review_attempts becomes 3
        allow(job_at_limit).to receive(:review_attempts).and_return(2, 3)
      end

      it "does not reschedule" do
        expect(ReviewRequestJob).not_to receive(:set)

        described_class.new.perform(47)
      end
    end

    context "when client has no name" do
      let(:client_no_name) { instance_double(Client, name: nil, phone: "5212219876543") }
      let(:job_no_name) do
        instance_double(
          Job,
          id: 48,
          review_sent?: false,
          review_attempts: 0,
          client: client_no_name,
          provider: provider
        )
      end

      before do
        allow(Job).to receive(:find_by).with(id: 48).and_return(job_no_name)
        allow(job_no_name).to receive(:update!)
        allow(job_no_name).to receive(:review_attempts).and_return(0, 1)
        allow(ReviewRequestJob).to receive_message_chain(:set, :perform_later)
        allow(WhatsAppService).to receive(:send_list_message)
      end

      it "sends List Message regardless of client name (name not used in List Message)" do
        expect(WhatsAppService).to receive(:send_list_message).with(
          to: "5212219876543",
          payload: a_hash_including(
            type: "list",
            header: a_hash_including(text: "¿Cómo calificarías el trabajo?")
          )
        )

        described_class.new.perform(48)
      end
    end
  end

  describe ".calculate_delivery_time" do
    # Mexico City is UTC-6 (standard) / UTC-5 (DST)
    let(:mexico_city_tz) { ActiveSupport::TimeZone["America/Mexico_City"] }

    context "when completed at 10:00 am CDMX" do
      it "schedules for 11:00 am CDMX the next day (24h window pushes past same-day 11am)" do
        # 10:00 am CDMX → 24h later = 10:00 am next day → 11am same day is after, so it works
        completed_at = mexico_city_tz.local(2025, 4, 15, 10, 0, 0)
        delivery = described_class.calculate_delivery_time(completed_at)

        expect(delivery.hour).to eq(11)
        expect(delivery.min).to eq(0)
        expect(delivery.day).to eq(16)
        expect(delivery.time_zone.name).to eq("America/Mexico_City")
        expect(delivery).to be > completed_at + 24.hours
      end
    end

    context "when completed at 11:00 am CDMX exactly" do
      it "schedules for 11:00 am CDMX two days later (not at exact 24h mark)" do
        # 11:00 am CDMX → 24h later = 11:00 am next day → candidate == earliest, push to day after
        completed_at = mexico_city_tz.local(2025, 4, 15, 11, 0, 0)
        delivery = described_class.calculate_delivery_time(completed_at)

        expect(delivery.hour).to eq(11)
        expect(delivery.min).to eq(0)
        expect(delivery.day).to eq(17)
        expect(delivery).to be > completed_at + 24.hours
      end
    end

    context "when completed at 11:30 am CDMX" do
      it "schedules for 11:00 am CDMX two days later" do
        # 11:30 am → 24h later = 11:30 am next day → 11am candidate is before, push to day after
        completed_at = mexico_city_tz.local(2025, 4, 15, 11, 30, 0)
        delivery = described_class.calculate_delivery_time(completed_at)

        expect(delivery.hour).to eq(11)
        expect(delivery.min).to eq(0)
        expect(delivery.day).to eq(17)
        expect(delivery).to be > completed_at + 24.hours
      end
    end

    context "when completed at 3:00 pm CDMX" do
      it "schedules for 11:00 am CDMX two days later" do
        # 3:00 pm → 24h later = 3:00 pm next day → 11am candidate is before, push to day after
        completed_at = mexico_city_tz.local(2025, 4, 15, 15, 0, 0)
        delivery = described_class.calculate_delivery_time(completed_at)

        expect(delivery.hour).to eq(11)
        expect(delivery.min).to eq(0)
        expect(delivery.day).to eq(17)
        expect(delivery).to be > completed_at + 24.hours
      end
    end

    context "when completed at midnight CDMX" do
      it "schedules for 11:00 am CDMX the next day" do
        # Midnight → 24h later = midnight next day → 11am that day is after midnight
        completed_at = mexico_city_tz.local(2025, 4, 15, 0, 0, 0)
        delivery = described_class.calculate_delivery_time(completed_at)

        expect(delivery.hour).to eq(11)
        expect(delivery.min).to eq(0)
        expect(delivery.day).to eq(16)
        expect(delivery).to be > completed_at + 24.hours
      end
    end

    context "when completed at 10:59 am CDMX" do
      it "schedules for 11:00 am CDMX the next day" do
        # 10:59 am → 24h later = 10:59 am next day → 11am is after, so it works
        completed_at = mexico_city_tz.local(2025, 4, 15, 10, 59, 0)
        delivery = described_class.calculate_delivery_time(completed_at)

        expect(delivery.hour).to eq(11)
        expect(delivery.min).to eq(0)
        expect(delivery.day).to eq(16)
        expect(delivery).to be > completed_at + 24.hours
      end
    end

    context "when completed in a different timezone (UTC)" do
      it "correctly converts and schedules at 11:00 am CDMX" do
        # 5:00 pm UTC = 11:00 am CDMX → same as 11am case, should go to +2 days
        completed_at = Time.utc(2025, 4, 15, 17, 0, 0)
        delivery = described_class.calculate_delivery_time(completed_at)

        expect(delivery.hour).to eq(11)
        expect(delivery.min).to eq(0)
        expect(delivery.time_zone.name).to eq("America/Mexico_City")
        expect(delivery).to be > completed_at + 24.hours
      end
    end

    it "always returns a time in the Mexico City timezone" do
      completed_at = Time.utc(2025, 6, 1, 12, 0, 0)
      delivery = described_class.calculate_delivery_time(completed_at)

      expect(delivery.time_zone.name).to eq("America/Mexico_City")
    end

    it "always returns a time at exactly 11:00:00" do
      completed_at = Time.utc(2025, 7, 20, 3, 45, 22)
      delivery = described_class.calculate_delivery_time(completed_at)

      expect(delivery.hour).to eq(11)
      expect(delivery.min).to eq(0)
      expect(delivery.sec).to eq(0)
    end
  end
end
