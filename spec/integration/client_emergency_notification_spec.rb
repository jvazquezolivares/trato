# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client Emergency Notification Flow Integration (C5A)", type: :request do
  include ActiveJob::TestHelper

  let(:client_phone_number_id) { "987654321" }
  let(:client_phone) { "5219511234567" }
  let(:provider_short_uuid) { "abc123" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_CLIENT_PHONE_NUMBER_ID").and_return(client_phone_number_id)
    allow(ENV).to receive(:[]).with("WHATSAPP_PROVIDER_PHONE_NUMBER_ID").and_return("123456789")
    clear_enqueued_jobs
  end

  describe "C5A emergency notification to both parties" do
    context "when testing with real database records" do
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

      let!(:conversation) do
        Conversation.create!(
          provider: provider,
          client: client_record,
          phone: client_phone,
          role: "client",
          stage: "active",
          context: {},
          last_message_at: Time.current
        )
      end

      before do
        # Mock WhatsApp service to capture messages
        allow(WhatsAppService).to receive(:send_message).and_return(nil)
        allow(WhatsAppService).to receive(:send_list_message).and_return(nil)
        allow(WhatsAppService).to receive(:send_message_with_buttons).and_return(nil)

        # Mock ClaudeService to avoid real API calls
        allow(ClaudeService).to receive(:call).and_return(
          {
            "message" => "Entiendo tu preocupación. Te estoy conectando con el técnico.",
            "action" => "none",
            "action_data" => {},
            "new_stage" => nil,
            "updated_context" => {},
            "should_save_message" => true
          }
        )

        # Allow real escalation detector to run
        allow(Assistants::EscalationDetector).to receive(:call).and_call_original
        allow(Assistants::EscalationDetector).to receive(:escalate!).and_call_original

        # Mock ClientMessageJob to directly call ClientAssistantOrchestrator with provider context
        allow(ClientMessageJob).to receive(:perform_later) do |from, body, media_url|
          ClientAssistantOrchestrator.call(
            provider: provider,
            from: from,
            body: body
          )
        end
      end

      context "when client reports electrical emergency with 'humo'" do
        let(:emergency_message) { "Hay humo y chispas en el panel eléctrico" }

        it "sends emergency alert to both client and provider synchronously" do
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
                          text: { body: emergency_message }
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

          # Verify both emergency messages were sent
          expect(WhatsAppService).to have_received(:send_message).at_least(2).times

          # Verify client received emergency alert with provider phone
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente.*llama a Miguel AHORA.*📞 5212291234567.*Si hay riesgo de incendio: llama al 911/m)
            )
          )

          # Verify provider received emergency alert with client info and detected keyword
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta (humo|chispas).*Su número: 📞 5219511234567.*Contáctala de inmediato/m)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end

        it "sends messages in correct order: client first, then provider" do
          call_order = []
          allow(WhatsAppService).to receive(:send_message) do |args|
            call_order << {
              to: args[:to],
              message_type: args[:message].include?("🚨") ? "emergency" : "general",
              timestamp: Time.current
            }
          end

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
                          text: { body: emergency_message }
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

          # Filter only emergency messages
          emergency_messages = call_order.select { |msg| msg[:message_type] == "emergency" }

          # Verify we have exactly 2 emergency messages
          expect(emergency_messages.length).to eq(2)

          # Verify order: client emergency alert first, then provider emergency alert
          expect(emergency_messages[0][:to]).to eq(client_phone)
          expect(emergency_messages[1][:to]).to eq(provider.phone)
        end
      end

      context "when client reports gas emergency" do
        let(:emergency_message) { "Huele a gas en la cocina, creo que hay una fuga" }

        it "detects 'gas' keyword and sends dual emergency alerts" do
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
                          text: { body: emergency_message }
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

          # Verify client received emergency alert
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente/)
            )
          )

          # Verify provider received emergency alert with 'gas' keyword
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta (gas|fuga de gas)/)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end
      end

      context "when client reports water emergency" do
        let(:emergency_message) { "Se reventó la tubería y hay inundación en el baño" }

        it "detects 'inundación' keyword and sends dual emergency alerts" do
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
                          text: { body: emergency_message }
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

          # Verify both emergency messages were sent
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente/)
            )
          )

          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta (inundación|se reventó)/)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end
      end

      context "when client reports fire emergency" do
        let(:emergency_message) { "¡Hay fuego en el panel! ¡Ayuda!" }

        it "detects 'fuego' keyword and sends dual emergency alerts" do
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
                          text: { body: emergency_message }
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

          # Verify client received emergency alert with 911 instruction
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente.*Si hay riesgo de incendio: llama al 911/m)
            )
          )

          # Verify provider received emergency alert with 'fuego' keyword
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta fuego/)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end
      end

      context "when client reports structural emergency" do
        let(:emergency_message) { "Se cayó parte del techo, hay un derrumbe" }

        it "detects 'derrumbe' keyword and sends dual emergency alerts" do
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
                          text: { body: emergency_message }
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

          # Verify both emergency messages were sent
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente/)
            )
          )

          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta (derrumbe|se cayó)/)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end
      end

      context "when client reports general emergency" do
        let(:emergency_message) { "¡Emergencia! ¡Necesito ayuda urgente!" }

        it "detects 'emergencia' keyword and sends dual emergency alerts" do
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
                          text: { body: emergency_message }
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

          # Verify both emergency messages were sent
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente/)
            )
          )

          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta (emergencia|ayuda urgente)/)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end
      end

      context "when client sends non-emergency message" do
        let(:normal_message) { "Hola, quisiera agendar una cita para mañana" }

        it "does not send emergency alerts for normal messages" do
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
                          text: { body: normal_message }
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

          # Verify no emergency messages were sent
          expect(WhatsAppService).not_to have_received(:send_message).with(
            hash_including(
              message: a_string_matching(/🚨/)
            )
          )

          # Verify conversation stage was NOT set to escalated
          conversation.reload
          expect(conversation.stage).not_to eq("escalated")
        end
      end

      context "when client has no name in database" do
        before do
          client_record.update!(name: nil)
        end

        let(:emergency_message) { "Hay chispas en el enchufe" }

        it "uses 'Cliente' as fallback name in emergency alerts" do
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
                          text: { body: emergency_message }
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

          # Verify client received emergency alert with fallback name
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Cliente, esto suena urgente/)
            )
          )

          # Verify provider received emergency alert with fallback name
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Cliente reporta/)
            )
          )
        end
      end

      context "when multiple danger keywords are present" do
        let(:emergency_message) { "Hay humo, chispas y olor a quemado en el panel" }

        it "detects the first matching keyword and sends dual emergency alerts" do
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
                          text: { body: emergency_message }
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

          # Verify both emergency messages were sent
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente/)
            )
          )

          # Verify provider received emergency alert with one of the detected keywords
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta (olor a quemado|humo|chispas)/)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end
      end

      context "when emergency is detected in mixed case message" do
        let(:emergency_message) { "HAY HUMO Y CHISPAS EN EL PANEL ELÉCTRICO" }

        it "detects emergency keywords case-insensitively" do
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
                          text: { body: emergency_message }
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

          # Verify both emergency messages were sent
          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: client_phone,
              message: a_string_matching(/🚨 Mariana, esto suena urgente/)
            )
          )

          expect(WhatsAppService).to have_received(:send_message).with(
            hash_including(
              to: provider.phone,
              message: a_string_matching(/🚨 URGENTE: Tu cliente Mariana reporta/)
            )
          )

          # Verify conversation stage was set to escalated
          conversation.reload
          expect(conversation.stage).to eq("escalated")
        end
      end
    end
  end
end
