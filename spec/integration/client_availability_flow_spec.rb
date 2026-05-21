# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client Dynamic Availability Flow Integration (C1A)", type: :request do
  include ActiveJob::TestHelper

  let(:client_phone_number_id) { "987654321" }
  let(:client_phone) { "5219511234567" }
  let(:provider_short_uuid) { "abc123" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_CLIENT_PHONE_NUMBER_ID").and_return(client_phone_number_id)
    allow(ClientAssistantOrchestrator).to receive(:call_search_mode).and_return(nil)
    clear_enqueued_jobs
  end

  describe "webhook routing to ClientMessageJob" do
    it "routes client messages to ClientMessageJob" do
      webhook_payload = {
        entry: [
          {
            changes: [
              {
                value: {
                  metadata: { phone_number_id: client_phone_number_id },
                  messages: [
                    {
                      from: client_phone,
                      type: "text",
                      text: { body: provider_short_uuid }
                    }
                  ]
                }
              }
            ]
          }
        ]
      }

      post "/webhooks/whatsapp", params: webhook_payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(ClientMessageJob).to have_been_enqueued

      perform_enqueued_jobs

      expect(ClientAssistantOrchestrator).to have_received(:call_search_mode).with(
        from: client_phone,
        body: provider_short_uuid
      )
    end
  end

  describe "C1A availability flow scenarios" do
    context "when testing with real database records" do
      let(:tomorrow) { Date.tomorrow }
      let!(:provider) do
        Provider.create!(
          name: "Miguel",
          phone: "5212291234567",
          short_uuid: provider_short_uuid,
          city: "Veracruz",
          active: true
        )
      end

      let!(:client_record) do
        Client.create!(
          name: "Mariana",
          phone: client_phone
        )
      end

      before do
        # Mock WhatsApp service
        allow(WhatsAppService).to receive(:send_message).and_return(nil)
        allow(WhatsAppService).to receive(:send_list_message).and_return(nil)
        allow(WhatsAppService).to receive(:send_message_with_buttons).and_return(nil)

        # Mock Redis
        redis_mock = instance_double(Redis)
        stub_const("REDIS", redis_mock)
        allow(redis_mock).to receive(:get).and_return(nil)
        allow(redis_mock).to receive(:setex).and_return("OK")
        allow(redis_mock).to receive(:del).and_return(1)

        # Allow real orchestrator to run
        allow(ClientAssistantOrchestrator).to receive(:call_search_mode).and_call_original
      end

      context "when WorkDay exists with available slots" do
        let!(:work_day) do
          WorkDay.create!(
            provider: provider,
            date: tomorrow,
            starts_at: Time.zone.parse("09:00"),
            ends_at: Time.zone.parse("18:00"),
            status: "active"
          )
        end

        let!(:existing_appointment) do
          Appointment.create!(
            provider: provider,
            client: client_record,
            work_day: work_day,
            scheduled_at: Time.zone.parse("#{tomorrow} 10:00"),
            estimated_duration: 60,
            status: "confirmed"
          )
        end

        it "generates available slots excluding taken appointments" do
          webhook_payload = {
            entry: [
              {
                changes: [
                  {
                    value: {
                      metadata: { phone_number_id: client_phone_number_id },
                      messages: [
                        {
                          from: client_phone,
                          type: "text",
                          text: { body: provider_short_uuid }
                        }
                      ]
                    }
                  }
                ]
              }
            ]
          }

          post "/webhooks/whatsapp", params: webhook_payload, as: :json
          perform_enqueued_jobs

          # Verify List Message was sent with available slots
          expect(WhatsAppService).to have_received(:send_list_message) do |args|
            expect(args[:to]).to eq(client_phone)
            payload = args[:payload]

            # Verify it's a list message for availability
            expect(payload[:type]).to eq("list")
            expect(payload[:header][:text]).to match(/Horarios disponibles|disponibles/i)

            # Verify slots are present
            rows = payload[:action][:sections][0][:rows]
            slot_times = rows.map { |row| row[:title] }

            # 10:00 should NOT be included (it's taken)
            expect(slot_times).not_to include("10:00")

            # 09:00 and 11:00 should be included (they're available)
            expect(slot_times).to include("09:00")
            expect(slot_times).to include("11:00")

            # Should have 8 slots (9 total - 1 taken)
            expect(rows.length).to eq(8)
          end
        end
      end

      context "when WorkDay does not exist" do
        it "sends escalation message" do
          webhook_payload = {
            entry: [
              {
                changes: [
                  {
                    value: {
                      metadata: { phone_number_id: client_phone_number_id },
                      messages: [
                        {
                          from: client_phone,
                          type: "text",
                          text: { body: provider_short_uuid }
                        }
                      ]
                    }
                  }
                ]
              }
            ]
          }

          post "/webhooks/whatsapp", params: webhook_payload, as: :json
          perform_enqueued_jobs

          # Verify escalation message was sent
          expect(WhatsAppService).to have_received(:send_message_with_buttons) do |args|
            expect(args[:to]).to eq(client_phone)
            expect(args[:message]).to match(/#{provider.name}.*no tiene.*agenda configurada/i)
            expect(args[:buttons]).to include(
              hash_including(id: "escalate_yes"),
              hash_including(id: "escalate_no")
            )
          end
        end
      end

      context "when WorkDay is fully booked" do
        let!(:work_day) do
          WorkDay.create!(
            provider: provider,
            date: tomorrow,
            starts_at: Time.zone.parse("09:00"),
            ends_at: Time.zone.parse("18:00"),
            status: "active"
          )
        end

        before do
          # Create appointments for all slots (9am-5pm)
          (9..17).each do |hour|
            Appointment.create!(
              provider: provider,
              client: client_record,
              work_day: work_day,
              scheduled_at: Time.zone.parse("#{tomorrow} #{hour}:00"),
              estimated_duration: 60,
              status: "confirmed"
            )
          end
        end

        it "sends escalation message when all slots are taken" do
          webhook_payload = {
            entry: [
              {
                changes: [
                  {
                    value: {
                      metadata: { phone_number_id: client_phone_number_id },
                      messages: [
                        {
                          from: client_phone,
                          type: "text",
                          text: { body: provider_short_uuid }
                        }
                      ]
                    }
                  }
                ]
              }
            ]
          }

          post "/webhooks/whatsapp", params: webhook_payload, as: :json
          perform_enqueued_jobs

          # Verify escalation message was sent (not List Message)
          expect(WhatsAppService).to have_received(:send_message_with_buttons) do |args|
            expect(args[:to]).to eq(client_phone)
            expect(args[:message]).to match(/no tiene.*disponible|agenda llena/i)
          end

          # Verify no List Message with slots was sent
          expect(WhatsAppService).not_to have_received(:send_list_message).with(
            hash_including(
              payload: hash_including(
                header: hash_including(text: /Horarios disponibles/)
              )
            )
          )
        end
      end
    end
  end
end
