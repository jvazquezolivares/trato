# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientAssistantOrchestrator, type: :service do
  describe "#find_next_available_work_day" do
    let(:provider) { instance_double(Provider, id: 1, name: "Miguel", phone: "5212291234567") }
    let(:from) { "5219511234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      # Stub work_days association
      allow(provider).to receive(:work_days).and_return(work_days_relation)
    end

    context "when provider has a WorkDay for tomorrow" do
      let(:tomorrow) { Date.tomorrow }
      let(:work_day) { instance_double(WorkDay, id: 1, date: tomorrow, provider_id: provider.id) }
      let(:work_days_relation) { double("work_days") }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(work_day)
      end

      it "returns the WorkDay for tomorrow" do
        result = orchestrator.send(:find_next_available_work_day, provider)

        expect(result).to eq(work_day)
      end

      it "queries for tomorrow's date first" do
        orchestrator.send(:find_next_available_work_day, provider)

        expect(work_days_relation).to have_received(:find_by).with(date: tomorrow)
      end
    end

    context "when provider has no WorkDay for tomorrow but has one in 2 days" do
      let(:tomorrow) { Date.tomorrow }
      let(:day_after_tomorrow) { Date.tomorrow + 1.day }
      let(:work_day) { instance_double(WorkDay, id: 2, date: day_after_tomorrow, provider_id: provider.id) }
      let(:work_days_relation) { double("work_days") }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: day_after_tomorrow).and_return(work_day)
      end

      it "returns the WorkDay for day after tomorrow" do
        result = orchestrator.send(:find_next_available_work_day, provider)

        expect(result).to eq(work_day)
      end

      it "queries for tomorrow first, then day after tomorrow" do
        orchestrator.send(:find_next_available_work_day, provider)

        expect(work_days_relation).to have_received(:find_by).with(date: tomorrow)
        expect(work_days_relation).to have_received(:find_by).with(date: day_after_tomorrow)
      end
    end

    context "when provider has a WorkDay on the 7th day from now" do
      let(:tomorrow) { Date.tomorrow }
      let(:seventh_day) { Date.tomorrow + 6.days }
      let(:work_day) { instance_double(WorkDay, id: 7, date: seventh_day, provider_id: provider.id) }
      let(:work_days_relation) { double("work_days") }

      before do
        # Mock all days returning nil except the 7th day
        (0..5).each do |days_ahead|
          allow(work_days_relation).to receive(:find_by).with(date: tomorrow + days_ahead.days).and_return(nil)
        end
        allow(work_days_relation).to receive(:find_by).with(date: seventh_day).and_return(work_day)
      end

      it "returns the WorkDay for the 7th day" do
        result = orchestrator.send(:find_next_available_work_day, provider)

        expect(result).to eq(work_day)
      end

      it "searches up to 7 days ahead" do
        orchestrator.send(:find_next_available_work_day, provider)

        (0..6).each do |days_ahead|
          expect(work_days_relation).to have_received(:find_by).with(date: tomorrow + days_ahead.days)
        end
      end
    end

    context "when provider has no WorkDay in the next 7 days" do
      let(:tomorrow) { Date.tomorrow }
      let(:work_days_relation) { double("work_days") }

      before do
        # Mock all days returning nil
        (0..6).each do |days_ahead|
          allow(work_days_relation).to receive(:find_by).with(date: tomorrow + days_ahead.days).and_return(nil)
        end
      end

      it "returns nil" do
        result = orchestrator.send(:find_next_available_work_day, provider)

        expect(result).to be_nil
      end

      it "searches all 7 days" do
        orchestrator.send(:find_next_available_work_day, provider)

        (0..6).each do |days_ahead|
          expect(work_days_relation).to have_received(:find_by).with(date: tomorrow + days_ahead.days)
        end
      end
    end

    context "when provider has multiple WorkDays in the next 7 days" do
      let(:tomorrow) { Date.tomorrow }
      let(:day_3) { Date.tomorrow + 2.days }
      let(:day_5) { Date.tomorrow + 4.days }
      let(:work_day_tomorrow) { instance_double(WorkDay, id: 1, date: tomorrow, provider_id: provider.id) }
      let(:work_day_day_3) { instance_double(WorkDay, id: 3, date: day_3, provider_id: provider.id) }
      let(:work_day_day_5) { instance_double(WorkDay, id: 5, date: day_5, provider_id: provider.id) }
      let(:work_days_relation) { double("work_days") }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(work_day_tomorrow)
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow + 1.day).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: day_3).and_return(work_day_day_3)
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow + 3.days).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: day_5).and_return(work_day_day_5)
      end

      it "returns the first WorkDay (tomorrow)" do
        result = orchestrator.send(:find_next_available_work_day, provider)

        expect(result).to eq(work_day_tomorrow)
      end

      it "stops searching after finding the first WorkDay" do
        orchestrator.send(:find_next_available_work_day, provider)

        # Should only query for tomorrow, not subsequent days
        expect(work_days_relation).to have_received(:find_by).with(date: tomorrow).once
        expect(work_days_relation).not_to have_received(:find_by).with(date: day_3)
        expect(work_days_relation).not_to have_received(:find_by).with(date: day_5)
      end
    end
  end

  describe "#send_no_work_day_escalation" do
    let(:provider) { instance_double(Provider, id: 1, name: "Miguel", phone: "5212291234567") }
    let(:from) { "5219511234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }

    before do
      allow(WhatsAppService).to receive(:send_message_with_buttons)
      allow(Rails.logger).to receive(:info)
      allow(orchestrator).to receive(:store_search_context)
    end

    it "sends escalation message with provider name" do
      orchestrator.send(:send_no_work_day_escalation, provider)

      expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
        to: from,
        message: "Miguel no tiene su agenda configurada para mañana. ¿Quieres que le avise para que te contacte directamente?",
        buttons: [
          { id: "escalate_yes", title: "Sí, avísale" },
          { id: "escalate_no", title: "No, gracias" }
        ]
      )
    end

    it "stores escalation context" do
      orchestrator.send(:send_no_work_day_escalation, provider)

      expect(orchestrator).to have_received(:store_search_context).with(
        provider_id: 1,
        provider_name: "Miguel",
        stage: "appointment_escalation",
        escalation_reason: "no_work_day"
      )
    end

    it "logs the escalation event" do
      orchestrator.send(:send_no_work_day_escalation, provider)

      expect(Rails.logger).to have_received(:info).with(
        "[ClientAssistantOrchestrator] No WorkDay found for Miguel. Sent escalation message to #{from}"
      )
    end

    context "when provider has a different name" do
      let(:provider) { instance_double(Provider, id: 2, name: "Carlos", phone: "5212291234568") }

      it "uses the correct provider name in the message" do
        orchestrator.send(:send_no_work_day_escalation, provider)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "Carlos no tiene su agenda configurada para mañana. ¿Quieres que le avise para que te contacte directamente?",
          buttons: [
            { id: "escalate_yes", title: "Sí, avísale" },
            { id: "escalate_no", title: "No, gracias" }
          ]
        )
      end

      it "stores correct provider info in context" do
        orchestrator.send(:send_no_work_day_escalation, provider)

        expect(orchestrator).to have_received(:store_search_context).with(
          provider_id: 2,
          provider_name: "Carlos",
          stage: "appointment_escalation",
          escalation_reason: "no_work_day"
        )
      end
    end
  end

  describe "#transition_to_appointment_flow" do
    let(:provider) { instance_double(Provider, id: 1, name: "Miguel", phone: "5212291234567", work_days: work_days_relation) }
    let(:from) { "5219511234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:search_context) do
      {
        detected_state: "Veracruz",
        region_scope: "state",
        selected_zone: "Centro Histórico",
        selected_category: "plomeria"
      }
    end
    let(:client) { instance_double(Client, id: 1, phone: from, new_record?: false) }
    let(:conversation) { instance_double(Conversation, id: 1, context: {}) }
    let(:work_days_relation) { double("work_days") }

    before do
      allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
      allow(client).to receive(:save!)
      allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
      allow(conversation).to receive(:client=)
      allow(conversation).to receive(:stage=)
      allow(conversation).to receive(:context=)
      allow(conversation).to receive(:last_message_at=)
      allow(conversation).to receive(:update!)
      allow(REDIS).to receive(:del)
      allow(WhatsAppService).to receive(:send_message)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
      allow(Rails.logger).to receive(:info)
    end

    context "when provider has a WorkDay for tomorrow" do
      let(:tomorrow) { Date.tomorrow }
      let(:work_day) { instance_double(WorkDay, id: 1, date: tomorrow, provider_id: provider.id, appointments: appointments_relation, starts_at: Time.zone.parse("09:00"), ends_at: Time.zone.parse("18:00")) }
      let(:appointments_relation) { double("appointments") }
      let(:appointments_query) { double("appointments_query") }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(work_day)
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).and_return(appointments_query)
        allow(appointments_query).to receive(:order).and_return([])
      end

      it "finds the next available WorkDay" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(work_days_relation).to have_received(:find_by).with(date: tomorrow)
      end

      it "queries existing appointments for the WorkDay" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(appointments_relation).to have_received(:where)
        expect(appointments_query).to have_received(:not).with(status: "cancelled")
        expect(appointments_query).to have_received(:order).with(:scheduled_at)
      end

      it "logs the WorkDay found" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Found WorkDay for Miguel on #{work_day.date}"
        )
      end

      it "logs the number of existing appointments" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Found 0 existing appointments for WorkDay 1"
        )
      end

      it "does not send escalation message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).not_to have_received(:send_message_with_buttons).with(
          hash_including(message: /no tiene su agenda configurada/)
        )
      end
    end

    context "when provider has no WorkDay in the next 7 days" do
      let(:tomorrow) { Date.tomorrow }

      before do
        (0..6).each do |days_ahead|
          allow(work_days_relation).to receive(:find_by).with(date: tomorrow + days_ahead.days).and_return(nil)
        end
      end

      it "searches for WorkDay in the next 7 days" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        (0..6).each do |days_ahead|
          expect(work_days_relation).to have_received(:find_by).with(date: tomorrow + days_ahead.days)
        end
      end

      it "sends escalation message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "Miguel no tiene su agenda configurada para mañana. ¿Quieres que le avise para que te contacte directamente?",
          buttons: [
            { id: "escalate_yes", title: "Sí, avísale" },
            { id: "escalate_no", title: "No, gracias" }
          ]
        )
      end

      it "logs the no WorkDay event" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] No WorkDay found for Miguel. Sent escalation message to #{from}"
        )
      end
    end

    context "when provider has a WorkDay in 3 days" do
      let(:tomorrow) { Date.tomorrow }
      let(:day_3) { Date.tomorrow + 2.days }
      let(:work_day) { instance_double(WorkDay, id: 3, date: day_3, provider_id: provider.id, appointments: appointments_relation, starts_at: Time.zone.parse("09:00"), ends_at: Time.zone.parse("18:00")) }
      let(:appointments_relation) { double("appointments") }
      let(:appointments_query) { double("appointments_query") }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow + 1.day).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: day_3).and_return(work_day)
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).and_return(appointments_query)
        allow(appointments_query).to receive(:order).and_return([])
      end

      it "finds the WorkDay on day 3" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(work_days_relation).to have_received(:find_by).with(date: day_3)
      end

      it "logs the WorkDay found" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Found WorkDay for Miguel on #{work_day.date}"
        )
      end

      it "does not send escalation message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).not_to have_received(:send_message_with_buttons).with(
          hash_including(message: /no tiene su agenda configurada/)
        )
      end
    end

    context "when client and conversation are created successfully" do
      let(:tomorrow) { Date.tomorrow }
      let(:work_day) { instance_double(WorkDay, id: 1, date: tomorrow, provider_id: provider.id, appointments: appointments_relation, starts_at: Time.zone.parse("09:00"), ends_at: Time.zone.parse("18:00")) }
      let(:appointments_relation) { double("appointments") }
      let(:appointments_query) { double("appointments_query") }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(work_day)
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).and_return(appointments_query)
        allow(appointments_query).to receive(:order).and_return([])
      end

      it "creates or finds client record" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Client).to have_received(:find_or_initialize_by).with(phone: from)
      end

      it "creates or finds conversation record" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Conversation).to have_received(:find_or_create_by!)
      end

      it "updates conversation with appointment_scheduling stage" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(conversation).to have_received(:update!).with(
          stage: "appointment_scheduling",
          context: hash_including(
            selected_zone: "Centro Histórico",
            selected_category: "plomeria",
            discovery_method: "c2a_region_based"
          ),
          last_message_at: kind_of(ActiveSupport::TimeWithZone)
        )
      end

      it "clears search context from Redis" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(REDIS).to have_received(:del).with("client_search:#{from}")
      end

      it "sends confirmation message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Perfecto, seleccionaste a Miguel. Ahora vamos a agendar tu cita..."
        )
      end
    end
  end

  describe "#query_appointments_for_work_day" do
    let(:from) { "5219511234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:work_day) { instance_double(WorkDay, id: 1, date: Date.tomorrow, appointments: appointments_relation) }
    let(:appointments_relation) { double("appointments") }

    context "when WorkDay has no appointments" do
      let(:appointments_query) { double("appointments_query") }

      before do
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).with(status: "cancelled").and_return(appointments_query)
        allow(appointments_query).to receive(:order).with(:scheduled_at).and_return([])
      end

      it "returns empty array" do
        result = orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(result).to eq([])
      end

      it "queries appointments excluding cancelled status" do
        orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(appointments_relation).to have_received(:where)
        expect(appointments_query).to have_received(:not).with(status: "cancelled")
      end

      it "orders appointments by scheduled_at" do
        orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(appointments_query).to have_received(:order).with(:scheduled_at)
      end
    end

    context "when WorkDay has confirmed and pending appointments" do
      let(:appointments_query) { double("appointments_query") }
      let(:appointment1) { instance_double(Appointment, id: 1, status: "confirmed", scheduled_at: Time.current + 2.hours) }
      let(:appointment2) { instance_double(Appointment, id: 2, status: "pending", scheduled_at: Time.current + 4.hours) }

      before do
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).with(status: "cancelled").and_return(appointments_query)
        allow(appointments_query).to receive(:order).with(:scheduled_at).and_return([ appointment1, appointment2 ])
      end

      it "returns both appointments" do
        result = orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(result).to eq([ appointment1, appointment2 ])
      end

      it "returns appointments ordered by scheduled_at" do
        result = orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(result.first).to eq(appointment1)
        expect(result.last).to eq(appointment2)
      end
    end

    context "when WorkDay has cancelled appointments" do
      let(:appointments_query) { double("appointments_query") }
      let(:appointment1) { instance_double(Appointment, id: 1, status: "confirmed", scheduled_at: Time.current + 2.hours) }
      let(:appointment2) { instance_double(Appointment, id: 2, status: "cancelled", scheduled_at: Time.current + 4.hours) }

      before do
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).with(status: "cancelled").and_return(appointments_query)
        allow(appointments_query).to receive(:order).with(:scheduled_at).and_return([ appointment1 ])
      end

      it "excludes cancelled appointments" do
        result = orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(result).to eq([ appointment1 ])
        expect(result).not_to include(appointment2)
      end

      it "queries with not cancelled status" do
        orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(appointments_query).to have_received(:not).with(status: "cancelled")
      end
    end

    context "when WorkDay has multiple appointments with different statuses" do
      let(:appointments_query) { double("appointments_query") }
      let(:appointment1) { instance_double(Appointment, id: 1, status: "confirmed", scheduled_at: Time.current + 1.hour) }
      let(:appointment2) { instance_double(Appointment, id: 2, status: "pending", scheduled_at: Time.current + 3.hours) }
      let(:appointment3) { instance_double(Appointment, id: 3, status: "completed", scheduled_at: Time.current + 5.hours) }
      let(:appointment4) { instance_double(Appointment, id: 4, status: "cancelled", scheduled_at: Time.current + 7.hours) }

      before do
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).with(status: "cancelled").and_return(appointments_query)
        allow(appointments_query).to receive(:order).with(:scheduled_at).and_return([ appointment1, appointment2, appointment3 ])
      end

      it "returns all non-cancelled appointments" do
        result = orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(result).to eq([ appointment1, appointment2, appointment3 ])
        expect(result).not_to include(appointment4)
      end

      it "includes confirmed, pending, and completed appointments" do
        result = orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(result.map(&:status)).to contain_exactly("confirmed", "pending", "completed")
      end

      it "orders appointments by scheduled_at ascending" do
        result = orchestrator.send(:query_appointments_for_work_day, work_day)

        expect(result[0]).to eq(appointment1) # 1 hour
        expect(result[1]).to eq(appointment2) # 3 hours
        expect(result[2]).to eq(appointment3) # 5 hours
      end
    end
  end

  describe "#generate_available_slots" do
    let(:from) { "5219511234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:work_day_date) { Date.tomorrow }

    context "when WorkDay has 9am-6pm schedule with no appointments" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("18:00")
        )
      end
      let(:appointments) { [] }

      it "generates 9 hourly slots (9am-5pm)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.count).to eq(9)
      end

      it "generates slots starting at 9am" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.first[:display_time]).to eq("09:00")
      end

      it "generates slots ending at 5pm (last slot before 6pm end time)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.last[:display_time]).to eq("17:00")
      end

      it "generates slots with correct time objects" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.first[:time]).to be_a(Time)
        expect(result.first[:time].hour).to eq(9)
      end

      it "generates slots with correct display format" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).to eq([
          "09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00", "17:00"
        ])
      end
    end

    context "when WorkDay has 8am-5pm schedule" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("08:00"),
          ends_at: Time.zone.parse("17:00")
        )
      end
      let(:appointments) { [] }

      it "generates 9 hourly slots (8am-4pm)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.count).to eq(9)
      end

      it "generates slots from 8am to 4pm" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).to eq([
          "08:00", "09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00"
        ])
      end
    end

    context "when WorkDay has one appointment at 10am (60 min duration)" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("18:00")
        )
      end
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment] }

      it "excludes the 10am slot" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).not_to include("10:00")
      end

      it "includes the 9am slot (before appointment)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).to include("09:00")
      end

      it "includes the 11am slot (after appointment)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).to include("11:00")
      end

      it "returns 8 available slots (9 total - 1 taken)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.count).to eq(8)
      end
    end

    context "when WorkDay has appointment at 2pm (90 min duration)" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("18:00")
        )
      end
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 14:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 90
        )
      end
      let(:appointments) { [appointment] }

      it "excludes the 2pm slot (appointment start)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).not_to include("14:00")
      end

      it "excludes the 3pm slot (within appointment duration)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).not_to include("15:00")
      end

      it "includes the 1pm slot (before appointment)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).to include("13:00")
      end

      it "includes the 4pm slot (after appointment ends at 3:30pm)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).to include("16:00")
      end

      it "returns 7 available slots (9 total - 2 taken)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.count).to eq(7)
      end
    end

    context "when WorkDay has multiple appointments" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("18:00")
        )
      end
      let(:appointment1_time) { Time.zone.parse("#{work_day_date} 09:00") }
      let(:appointment2_time) { Time.zone.parse("#{work_day_date} 11:00") }
      let(:appointment3_time) { Time.zone.parse("#{work_day_date} 15:00") }
      let(:appointment1) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment1_time,
          estimated_duration: 60
        )
      end
      let(:appointment2) do
        instance_double(
          Appointment,
          id: 2,
          scheduled_at: appointment2_time,
          estimated_duration: 60
        )
      end
      let(:appointment3) do
        instance_double(
          Appointment,
          id: 3,
          scheduled_at: appointment3_time,
          estimated_duration: 120
        )
      end
      let(:appointments) { [appointment1, appointment2, appointment3] }

      it "excludes all taken slots" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        taken_slots = ["09:00", "11:00", "15:00", "16:00"]
        result_times = result.map { |slot| slot[:display_time] }

        taken_slots.each do |taken_slot|
          expect(result_times).not_to include(taken_slot)
        end
      end

      it "includes available slots between appointments" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        available_slots = ["10:00", "12:00", "13:00", "14:00", "17:00"]
        result_times = result.map { |slot| slot[:display_time] }

        available_slots.each do |available_slot|
          expect(result_times).to include(available_slot)
        end
      end

      it "returns 5 available slots (9 total - 4 taken)" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.count).to eq(5)
      end
    end

    context "when WorkDay is fully booked" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("12:00")
        )
      end
      let(:appointment1_time) { Time.zone.parse("#{work_day_date} 09:00") }
      let(:appointment2_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment3_time) { Time.zone.parse("#{work_day_date} 11:00") }
      let(:appointment1) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment1_time,
          estimated_duration: 60
        )
      end
      let(:appointment2) do
        instance_double(
          Appointment,
          id: 2,
          scheduled_at: appointment2_time,
          estimated_duration: 60
        )
      end
      let(:appointment3) do
        instance_double(
          Appointment,
          id: 3,
          scheduled_at: appointment3_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment1, appointment2, appointment3] }

      it "returns empty array" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result).to eq([])
      end

      it "excludes all slots" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.count).to eq(0)
      end
    end

    context "when WorkDay has missing start_time" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: nil,
          ends_at: Time.zone.parse("18:00")
        )
      end
      let(:appointments) { [] }

      before do
        allow(Rails.logger).to receive(:warn)
      end

      it "returns empty array" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result).to eq([])
      end

      it "logs warning" do
        orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(Rails.logger).to have_received(:warn).with(
          "[ClientAssistantOrchestrator] WorkDay 1 missing start or end time"
        )
      end
    end

    context "when WorkDay has missing end_time" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("09:00"),
          ends_at: nil
        )
      end
      let(:appointments) { [] }

      before do
        allow(Rails.logger).to receive(:warn)
      end

      it "returns empty array" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result).to eq([])
      end

      it "logs warning" do
        orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(Rails.logger).to have_received(:warn).with(
          "[ClientAssistantOrchestrator] WorkDay 1 missing start or end time"
        )
      end
    end

    context "when WorkDay has appointment at edge of schedule" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: work_day_date,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("12:00")
        )
      end
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 09:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment] }

      it "excludes the first slot" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).not_to include("09:00")
      end

      it "includes remaining slots" do
        result = orchestrator.send(:generate_available_slots, work_day, appointments)

        expect(result.map { |slot| slot[:display_time] }).to eq(["10:00", "11:00"])
      end
    end
  end

  describe "#slot_taken?" do
    let(:from) { "5219511234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:work_day_date) { Date.tomorrow }

    context "when slot is before appointment" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 09:00") }
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment] }

      it "returns false" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be false
      end
    end

    context "when slot is after appointment" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 12:00") }
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment] }

      it "returns false" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be false
      end
    end

    context "when slot is exactly at appointment start time" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment] }

      it "returns true" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be true
      end
    end

    context "when slot is within appointment duration" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 10:30") }
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 90
        )
      end
      let(:appointments) { [appointment] }

      it "returns true" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be true
      end
    end

    context "when slot is exactly at appointment end time" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 11:00") }
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment] }

      it "returns false (slot starts when appointment ends)" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be false
      end
    end

    context "when checking against multiple appointments" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 11:00") }
      let(:appointment1_time) { Time.zone.parse("#{work_day_date} 09:00") }
      let(:appointment2_time) { Time.zone.parse("#{work_day_date} 11:00") }
      let(:appointment3_time) { Time.zone.parse("#{work_day_date} 14:00") }
      let(:appointment1) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment1_time,
          estimated_duration: 60
        )
      end
      let(:appointment2) do
        instance_double(
          Appointment,
          id: 2,
          scheduled_at: appointment2_time,
          estimated_duration: 60
        )
      end
      let(:appointment3) do
        instance_double(
          Appointment,
          id: 3,
          scheduled_at: appointment3_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment1, appointment2, appointment3] }

      it "returns true if slot overlaps with any appointment" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be true
      end
    end

    context "when checking slot between two appointments" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 11:00") }
      let(:appointment1_time) { Time.zone.parse("#{work_day_date} 09:00") }
      let(:appointment2_time) { Time.zone.parse("#{work_day_date} 13:00") }
      let(:appointment1) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment1_time,
          estimated_duration: 60
        )
      end
      let(:appointment2) do
        instance_double(
          Appointment,
          id: 2,
          scheduled_at: appointment2_time,
          estimated_duration: 60
        )
      end
      let(:appointments) { [appointment1, appointment2] }

      it "returns false" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be false
      end
    end

    context "when appointment has 120 minute duration" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 11:00") }
      let(:appointment_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 120
        )
      end
      let(:appointments) { [appointment] }

      it "returns true (slot within 2-hour appointment)" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be true
      end
    end

    context "when no appointments exist" do
      let(:slot_time) { Time.zone.parse("#{work_day_date} 10:00") }
      let(:appointments) { [] }

      it "returns false" do
        result = orchestrator.send(:slot_taken?, slot_time, appointments)

        expect(result).to be false
      end
    end
  end

  describe "#handle_appointment_escalation_response" do
    let(:provider) { instance_double(Provider, id: 1, name: "Miguel", phone: "5212291234567") }
    let(:from) { "5219511234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:search_context) do
      {
        provider_id: provider.id,
        provider_name: provider.name,
        stage: "appointment_escalation",
        escalation_reason: "no_work_day"
      }
    end

    before do
      allow(Provider).to receive(:find_by).with(id: provider.id).and_return(provider)
      allow(WhatsAppService).to receive(:send_message)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:error)
      allow(orchestrator).to receive(:clear_search_context)
      allow(orchestrator).to receive(:handle_escalation_confirmed)
      allow(orchestrator).to receive(:handle_escalation_declined)
    end

    context "when user confirms escalation with button ID" do
      let(:body) { "escalate_yes" }

      it "calls handle_escalation_confirmed" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(orchestrator).to have_received(:handle_escalation_confirmed).with(
          provider,
          "no_work_day"
        )
      end
    end

    context "when user confirms escalation with natural language" do
      let(:body) { "Sí, avísale" }

      it "calls handle_escalation_confirmed" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(orchestrator).to have_received(:handle_escalation_confirmed).with(
          provider,
          "no_work_day"
        )
      end
    end

    context "when user declines escalation with button ID" do
      let(:body) { "escalate_no" }

      it "calls handle_escalation_declined" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(orchestrator).to have_received(:handle_escalation_declined).with("Miguel")
      end
    end

    context "when user declines escalation with natural language" do
      let(:body) { "No, gracias" }

      it "calls handle_escalation_declined" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(orchestrator).to have_received(:handle_escalation_declined).with("Miguel")
      end
    end

    context "when user response is unclear" do
      let(:body) { "tal vez" }

      it "sends clarification message" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "No entendí tu respuesta. ¿Quieres que le avise a Miguel?"
        )
      end

      it "resends buttons" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "Por favor selecciona una opción:",
          buttons: [
            { id: "escalate_yes", title: "Sí, avísale" },
            { id: "escalate_no", title: "No, gracias" }
          ]
        )
      end
    end

    context "when provider is not found" do
      let(:body) { "escalate_yes" }

      before do
        allow(Provider).to receive(:find_by).with(id: provider.id).and_return(nil)
      end

      it "logs error" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(Rails.logger).to have_received(:error).with(
          "[ClientAssistantOrchestrator] Provider not found: #{provider.id}"
        )
      end

      it "sends error message to client" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Lo siento, hubo un problema. ¿Puedes intentar de nuevo?"
        )
      end

      it "clears search context" do
        orchestrator.send(:handle_appointment_escalation_response, search_context)

        expect(orchestrator).to have_received(:clear_search_context)
      end
    end
  end

  describe "#escalation_confirmed?" do
    let(:from) { "5219511234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: "test") }

    context "when body contains button ID" do
      it "returns true for escalate_yes" do
        result = orchestrator.send(:escalation_confirmed?, "escalate_yes")

        expect(result).to be true
      end
    end

    context "when body contains natural language confirmation" do
      it "returns true for 'Sí'" do
        result = orchestrator.send(:escalation_confirmed?, "Sí")

        expect(result).to be true
      end

      it "returns true for 'Si'" do
        result = orchestrator.send(:escalation_confirmed?, "Si")

        expect(result).to be true
      end

      it "returns true for 'yes'" do
        result = orchestrator.send(:escalation_confirmed?, "yes")

        expect(result).to be true
      end

      it "returns true for 'ok'" do
        result = orchestrator.send(:escalation_confirmed?, "ok")

        expect(result).to be true
      end

      it "returns true for 'dale'" do
        result = orchestrator.send(:escalation_confirmed?, "dale")

        expect(result).to be true
      end

      it "returns true for 'avísale'" do
        result = orchestrator.send(:escalation_confirmed?, "avísale")

        expect(result).to be true
      end
    end

    context "when body is blank" do
      it "returns false" do
        result = orchestrator.send(:escalation_confirmed?, "")

        expect(result).to be false
      end
    end

    context "when body does not match confirmation patterns" do
      it "returns false" do
        result = orchestrator.send(:escalation_confirmed?, "tal vez")

        expect(result).to be false
      end
    end
  end

  describe "#escalation_declined?" do
    let(:from) { "5219511234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: "test") }

    context "when body contains button ID" do
      it "returns true for escalate_no" do
        result = orchestrator.send(:escalation_declined?, "escalate_no")

        expect(result).to be true
      end
    end

    context "when body contains natural language decline" do
      it "returns true for 'no'" do
        result = orchestrator.send(:escalation_declined?, "no")

        expect(result).to be true
      end

      it "returns true for 'No, gracias'" do
        result = orchestrator.send(:escalation_declined?, "No, gracias")

        expect(result).to be true
      end

      it "returns true for 'nop'" do
        result = orchestrator.send(:escalation_declined?, "nop")

        expect(result).to be true
      end
    end

    context "when body is blank" do
      it "returns false" do
        result = orchestrator.send(:escalation_declined?, "")

        expect(result).to be false
      end
    end

    context "when body does not match decline patterns" do
      it "returns false" do
        result = orchestrator.send(:escalation_declined?, "tal vez")

        expect(result).to be false
      end
    end
  end

  describe "#handle_escalation_confirmed" do
    let(:provider) { instance_double(Provider, id: 1, name: "Miguel", phone: "5212291234567") }
    let(:from) { "5219511234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: "escalate_yes") }
    let(:escalation_reason) { "no_work_day" }
    let(:client) { instance_double(Client, id: 1, phone: from, save!: true, new_record?: false) }
    let(:conversation) do
      instance_double(
        Conversation,
        id: 1,
        provider: provider,
        phone: from,
        role: "client",
        stage: "active",
        context: {},
        update!: true
      )
    end

    before do
      allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
      allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
      allow(conversation).to receive(:context).and_return({})
      allow(conversation).to receive(:client=)
      allow(conversation).to receive(:stage=)
      allow(conversation).to receive(:context=)
      allow(conversation).to receive(:last_message_at=)
      allow(WhatsAppService).to receive(:send_message)
      allow(Rails.logger).to receive(:info)
      allow(orchestrator).to receive(:clear_search_context)
      allow(Time).to receive(:current).and_return(Time.zone.parse("2026-05-20 10:00:00"))
    end

    it "finds or creates client record" do
      orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

      expect(Client).to have_received(:find_or_initialize_by).with(phone: from)
    end

    it "finds or creates conversation record" do
      orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

      expect(Conversation).to have_received(:find_or_create_by!).with(
        provider: provider,
        phone: from,
        role: "client"
      )
    end

    it "updates conversation stage to escalated" do
      orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

      expect(conversation).to have_received(:update!).with(
        stage: "escalated",
        context: hash_including(
          escalation_reason: "no_work_day",
          escalated_at: "2026-05-20T10:00:00-06:00"
        ),
        last_message_at: Time.zone.parse("2026-05-20 10:00:00")
      )
    end

    it "sends notification to provider" do
      orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

      expect(WhatsAppService).to have_received(:send_message).with(
        to: provider.phone,
        message: "Hola Miguel, un cliente quiere agendar una cita contigo pero no tiene su agenda configurada. " \
                 "Su número es: #{from}. ¿Puedes contactarlo directamente?"
      )
    end

    it "sends confirmation to client" do
      orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

      expect(WhatsAppService).to have_received(:send_message).with(
        to: from,
        message: "Perfecto, le avisé a Miguel. Te contactará pronto para coordinar la cita. 😊"
      )
    end

    it "clears search context" do
      orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

      expect(orchestrator).to have_received(:clear_search_context)
    end

    it "logs the escalation event" do
      orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

      expect(Rails.logger).to have_received(:info).with(
        "[ClientAssistantOrchestrator] Escalation confirmed for provider Miguel (ID: 1). Notified provider and set conversation stage to escalated."
      )
    end

    context "when escalation reason is fully_booked" do
      let(:escalation_reason) { "fully_booked" }

      it "sends correct message to provider" do
        orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: "Hola Miguel, un cliente quiere agendar una cita contigo pero no tiene horarios disponibles. " \
                   "Su número es: #{from}. ¿Puedes contactarlo directamente?"
        )
      end
    end

    context "when client is new" do
      before do
        allow(client).to receive(:new_record?).and_return(true)
      end

      it "saves the new client" do
        orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(client).to have_received(:save!)
      end

      it "logs client creation" do
        orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Created new client record for #{from}"
        )
      end
    end
  end

  describe "#handle_escalation_declined" do
    let(:from) { "5219511234567" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: "escalate_no") }
    let(:provider_name) { "Miguel" }

    before do
      allow(WhatsAppService).to receive(:send_message)
      allow(Rails.logger).to receive(:info)
      allow(orchestrator).to receive(:clear_search_context)
    end

    it "sends closing message to client" do
      orchestrator.send(:handle_escalation_declined, provider_name)

      expect(WhatsAppService).to have_received(:send_message).with(
        to: from,
        message: "Entendido. Si cambias de opinión, puedes escribirme de nuevo. ¡Que tengas un buen día! 😊"
      )
    end

    it "clears search context" do
      orchestrator.send(:handle_escalation_declined, provider_name)

      expect(orchestrator).to have_received(:clear_search_context)
    end

    it "logs the declined escalation" do
      orchestrator.send(:handle_escalation_declined, provider_name)

      expect(Rails.logger).to have_received(:info).with(
        "[ClientAssistantOrchestrator] Escalation declined for provider Miguel. Sent closing message to #{from}"
      )
    end
  end

  # Task 19.7 - Tests for displaying available slots and escalation paths
  describe "Task 19: Display Available Slots or Escalation" do
    let(:provider) { instance_double(Provider, id: 1, name: "Miguel", phone: "5212291234567", work_days: work_days_relation) }
    let(:from) { "5219511234567" }
    let(:body) { "provider_123" }
    let(:orchestrator) { described_class.new_search_mode(from: from, body: body) }
    let(:search_context) do
      {
        detected_state: "Veracruz",
        region_scope: "state",
        selected_zone: "Centro Histórico",
        selected_category: "plomeria"
      }
    end
    let(:client) { instance_double(Client, id: 1, phone: from, new_record?: false) }
    let(:conversation) { instance_double(Conversation, id: 1, context: {}) }
    let(:work_days_relation) { double("work_days") }
    let(:tomorrow) { Date.tomorrow }

    before do
      allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
      allow(client).to receive(:save!)
      allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
      allow(conversation).to receive(:client=)
      allow(conversation).to receive(:stage=)
      allow(conversation).to receive(:context=)
      allow(conversation).to receive(:last_message_at=)
      allow(conversation).to receive(:update!)
      allow(REDIS).to receive(:del)
      allow(WhatsAppService).to receive(:send_message)
      allow(WhatsAppService).to receive(:send_message_with_buttons)
      allow(WhatsAppService).to receive(:send_list_message)
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)
    end

    context "when WorkDay exists with available slots (Path 1: Display slots)" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: tomorrow,
          provider_id: provider.id,
          appointments: appointments_relation,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("18:00")
        )
      end
      let(:appointments_relation) { double("appointments") }
      let(:appointments_query) { double("appointments_query") }
      let(:appointment_time) { Time.zone.parse("#{tomorrow} 10:00") }
      let(:appointment) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: appointment_time,
          estimated_duration: 60
        )
      end
      let(:available_slots) do
        [
          { time: Time.zone.parse("#{tomorrow} 09:00"), display_time: "09:00" },
          { time: Time.zone.parse("#{tomorrow} 11:00"), display_time: "11:00" },
          { time: Time.zone.parse("#{tomorrow} 12:00"), display_time: "12:00" }
        ]
      end

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(work_day)
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).and_return(appointments_query)
        allow(appointments_query).to receive(:order).and_return([appointment])
        allow(WhatsApp::ListMessageBuilder).to receive(:build_available_slots_list).and_return({
          type: "list",
          header: { type: "text", text: "Horarios disponibles — mañana" },
          body: { text: "Miguel tiene 3 horarios disponibles para mañana" },
          action: { button: "Ver horarios", sections: [] }
        })
      end

      it "sends List Message with available slots" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_list_message).with(
          to: from,
          payload: hash_including(
            type: "list",
            header: hash_including(text: "Horarios disponibles — mañana")
          )
        )
      end

      it "builds List Message with correct parameters" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsApp::ListMessageBuilder).to have_received(:build_available_slots_list).with(
          kind_of(Array),
          date: tomorrow,
          provider_name: "Miguel"
        )
      end

      it "logs the number of available slots sent" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).to have_received(:info).with(
          /Sent \d+ available slots to #{from} for WorkDay 1/
        )
      end

      it "does not send escalation message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).not_to have_received(:send_message_with_buttons).with(
          hash_including(buttons: array_including(hash_including(id: "escalate_yes")))
        )
      end
    end

    context "when WorkDay exists but is fully booked (Path 2: Escalation)" do
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: tomorrow,
          provider_id: provider.id,
          appointments: appointments_relation,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("12:00")
        )
      end
      let(:appointments_relation) { double("appointments") }
      let(:appointments_query) { double("appointments_query") }
      let(:appointment1) do
        instance_double(
          Appointment,
          id: 1,
          scheduled_at: Time.zone.parse("#{tomorrow} 09:00"),
          estimated_duration: 60
        )
      end
      let(:appointment2) do
        instance_double(
          Appointment,
          id: 2,
          scheduled_at: Time.zone.parse("#{tomorrow} 10:00"),
          estimated_duration: 60
        )
      end
      let(:appointment3) do
        instance_double(
          Appointment,
          id: 3,
          scheduled_at: Time.zone.parse("#{tomorrow} 11:00"),
          estimated_duration: 60
        )
      end

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(work_day)
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).and_return(appointments_query)
        allow(appointments_query).to receive(:order).and_return([appointment1, appointment2, appointment3])
        allow(orchestrator).to receive(:store_search_context)
      end

      it "sends fully booked message to client" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Lo siento, Miguel no tiene horarios disponibles para mañana. " \
                   "¿Quieres que le avise para que te contacte directamente?"
        )
      end

      it "sends escalation buttons" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "¿Qué prefieres?",
          buttons: [
            { id: "escalate_yes", title: "Sí, avísale" },
            { id: "escalate_no", title: "No, gracias" }
          ]
        )
      end

      it "stores escalation context with fully_booked reason" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(orchestrator).to have_received(:store_search_context).with(
          provider_id: 1,
          provider_name: "Miguel",
          stage: "appointment_escalation",
          escalation_reason: "fully_booked"
        )
      end

      it "logs the fully booked event" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] WorkDay 1 fully booked. Sent escalation message to #{from}"
        )
      end

      it "does not send List Message with slots" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).not_to have_received(:send_list_message)
      end
    end

    context "when WorkDay exists for future date (not tomorrow)" do
      let(:future_date) { Date.tomorrow + 3.days }
      let(:work_day) do
        instance_double(
          WorkDay,
          id: 1,
          date: future_date,
          provider_id: provider.id,
          appointments: appointments_relation,
          starts_at: Time.zone.parse("09:00"),
          ends_at: Time.zone.parse("18:00")
        )
      end
      let(:appointments_relation) { double("appointments") }
      let(:appointments_query) { double("appointments_query") }

      before do
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow + 1.day).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: tomorrow + 2.days).and_return(nil)
        allow(work_days_relation).to receive(:find_by).with(date: future_date).and_return(work_day)
        allow(appointments_relation).to receive(:where).and_return(appointments_query)
        allow(appointments_query).to receive(:not).and_return(appointments_query)
        allow(appointments_query).to receive(:order).and_return([])
        allow(WhatsApp::ListMessageBuilder).to receive(:build_available_slots_list).and_return({
          type: "list",
          header: { type: "text", text: "Horarios disponibles — #{future_date.strftime('%A %d de %B')}" },
          body: { text: "Miguel tiene horarios disponibles" },
          action: { button: "Ver horarios", sections: [] }
        })
      end

      it "sends List Message with formatted date in header" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsApp::ListMessageBuilder).to have_received(:build_available_slots_list).with(
          kind_of(Array),
          date: future_date,
          provider_name: "Miguel"
        )
      end

      it "sends fully booked message with formatted date when no slots available" do
        # Make all slots taken
        allow(appointments_query).to receive(:order).and_return([
          instance_double(Appointment, id: 1, scheduled_at: Time.zone.parse("#{future_date} 09:00"), estimated_duration: 540)
        ])

        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: /Lo siento, Miguel no tiene horarios disponibles para #{future_date.strftime('%A %d de %B')}/
        )
      end
    end

    context "when no WorkDay exists in next 7 days (Path 3: No WorkDay escalation)" do
      before do
        (0..6).each do |days_ahead|
          allow(work_days_relation).to receive(:find_by).with(date: tomorrow + days_ahead.days).and_return(nil)
        end
      end

      it "sends no WorkDay escalation message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).to have_received(:send_message_with_buttons).with(
          to: from,
          message: "Miguel no tiene su agenda configurada para mañana. ¿Quieres que le avise para que te contacte directamente?",
          buttons: [
            { id: "escalate_yes", title: "Sí, avísale" },
            { id: "escalate_no", title: "No, gracias" }
          ]
        )
      end

      it "does not send List Message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).not_to have_received(:send_list_message)
      end

      it "does not send fully booked message" do
        orchestrator.send(:transition_to_appointment_flow, provider, search_context)

        expect(WhatsAppService).not_to have_received(:send_message).with(
          hash_including(message: /no tiene horarios disponibles/)
        )
      end
    end

    # Task 19.8 - Test escalation notification to provider
    context "when client confirms escalation (Sí, avísale)" do
      let(:escalation_orchestrator) { described_class.new_search_mode(from: from, body: "escalate_yes") }
      let(:escalation_reason) { "no_work_day" }

      before do
        allow(Client).to receive(:find_or_initialize_by).with(phone: from).and_return(client)
        allow(Conversation).to receive(:find_or_create_by!).and_yield(conversation).and_return(conversation)
        allow(conversation).to receive(:provider).and_return(provider)
        allow(conversation).to receive(:update!)
        allow(escalation_orchestrator).to receive(:clear_search_context)
        allow(Time).to receive(:current).and_return(Time.zone.parse("2026-05-20 10:00:00"))
      end

      it "sends notification to provider with client phone number" do
        escalation_orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: provider.phone,
          message: "Hola Miguel, un cliente quiere agendar una cita contigo pero no tiene su agenda configurada. " \
                   "Su número es: #{from}. ¿Puedes contactarlo directamente?"
        )
      end

      it "sends confirmation message to client" do
        escalation_orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: from,
          message: "Perfecto, le avisé a Miguel. Te contactará pronto para coordinar la cita. 😊"
        )
      end

      it "sets conversation stage to escalated" do
        escalation_orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(conversation).to have_received(:update!).with(
          stage: "escalated",
          context: hash_including(
            escalation_reason: "no_work_day",
            escalated_at: "2026-05-20T10:00:00-06:00"
          ),
          last_message_at: Time.zone.parse("2026-05-20 10:00:00")
        )
      end

      it "logs the escalation notification event" do
        escalation_orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(Rails.logger).to have_received(:info).with(
          "[ClientAssistantOrchestrator] Escalation confirmed for provider Miguel (ID: 1). Notified provider and set conversation stage to escalated."
        )
      end

      it "clears search context after escalation" do
        escalation_orchestrator.send(:handle_escalation_confirmed, provider, escalation_reason)

        expect(escalation_orchestrator).to have_received(:clear_search_context)
      end
    end
  end
end
