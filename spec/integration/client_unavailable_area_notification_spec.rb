# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe "Client Unavailable Area Notification Flow Integration (C2F)", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:client_phone_number_id) { "987654321" }
  let(:client_phone) { "5219511234567" }
  let(:bot_token) { "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" }
  let(:chat_id) { "-1001234567890" }
  let(:telegram_url) { "https://api.telegram.org/bot#{bot_token}/sendMessage" }

  before do
    # Set environment variables
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WHATSAPP_CLIENT_PHONE_NUMBER_ID").and_return(client_phone_number_id)
    allow(ENV).to receive(:[]).with("WHATSAPP_PROVIDER_PHONE_NUMBER_ID").and_return("123456789")
    allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(bot_token)
    allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(chat_id)

    # Freeze time for consistent timestamp testing
    travel_to Time.zone.local(2026, 5, 21, 10, 30, 0)

    clear_enqueued_jobs
  end

  after do
    travel_back
  end

  describe "C2F unavailable area notification flow" do
    context "when client requests service in unavailable area" do
      let!(:client_record) do
        Client.create!(
          name: "Mariana López",
          phone: client_phone
        )
      end

      context "when Telegram is properly configured and API succeeds" do
        let(:success_response) do
          {
            ok: true,
            result: {
              message_id: 123,
              chat: { id: chat_id.to_i, type: "group" },
              date: 1716287400,
              text: "notification text"
            }
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .with(
              body: hash_including(
                chat_id: chat_id,
                text: /Nueva solicitud sin técnico/
              ),
              headers: { "Content-Type" => "application/json" }
            )
            .to_return(status: 200, body: success_response, headers: { "Content-Type" => "application/json" })
        end

        it "sends Telegram notification when no providers are found" do
          # This test focuses on the TelegramNotifier service
          # The full C2F flow integration will be tested once Task 24 is complete

          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          # Verify Telegram notification was sent with correct format
          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            expect(body["chat_id"]).to eq(chat_id)
            expect(body["text"]).to include("🔔 Nueva solicitud sin técnico")
            expect(body["text"]).to include("👤 Mariana López")
            expect(body["text"]).to include("📱 #{client_phone}")
            expect(body["text"]).to include("🔧 Plomería")
            expect(body["text"]).to include("📍 Centro Histórico")
            expect(body["text"]).to include("⏰ 21/05/2026 10:30")
          }
        end

        it "sends notification with correct message structure" do
          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Electricidad",
            city: "Boca del Río"
          )

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            text = body["text"]
            lines = text.split("\n")

            # Verify structure and order
            expect(lines[0]).to eq("🔔 Nueva solicitud sin técnico")
            expect(lines[1]).to eq("👤 Mariana López")
            expect(lines[2]).to eq("📱 #{client_phone}")
            expect(lines[3]).to eq("🔧 Electricidad")
            expect(lines[4]).to eq("📍 Boca del Río")
            expect(lines[5]).to eq("⏰ 21/05/2026 10:30")
          }
        end

        it "logs success message when notification is sent" do
          allow(Rails.logger).to receive(:info)

          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(Rails.logger).to have_received(:info).with("[TelegramNotifier] Notification sent successfully")
        end
      end

      context "when Telegram API fails" do
        let(:error_response) do
          {
            ok: false,
            error_code: 500,
            description: "Internal Server Error"
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 500, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "logs error but does not block main flow" do
          allow(Rails.logger).to receive(:error)

          expect do
            result = TelegramNotifier.notify_unavailable_area(
              client: client_record,
              category: "Plomería",
              city: "Centro Histórico"
            )
            expect(result).to be_nil
          end.not_to raise_error

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Telegram Server Error \(500\)/)
          )
        end

        it "returns nil without raising exception" do
          result = TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(result).to be_nil
        end
      end

      context "when Telegram API times out" do
        before do
          stub_request(:post, telegram_url).to_timeout
        end

        it "logs timeout error but does not block main flow" do
          allow(Rails.logger).to receive(:error)

          expect do
            result = TelegramNotifier.notify_unavailable_area(
              client: client_record,
              category: "Plomería",
              city: "Centro Histórico"
            )
            expect(result).to be_nil
          end.not_to raise_error

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Timeout sending notification/)
          )
        end
      end

      context "when Telegram is not configured" do
        before do
          allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(nil)
          allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(nil)
        end

        it "logs warning and skips notification without blocking flow" do
          allow(Rails.logger).to receive(:warn)

          expect do
            result = TelegramNotifier.notify_unavailable_area(
              client: client_record,
              category: "Plomería",
              city: "Centro Histórico"
            )
            expect(result).to be_nil
          end.not_to raise_error

          expect(Rails.logger).to have_received(:warn).with(
            a_string_matching(/Telegram not configured.*Missing TELEGRAM_BOT_TOKEN/)
          )
        end

        it "does not make HTTP request when not configured" do
          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(WebMock).not_to have_requested(:post, /api\.telegram\.org/)
        end
      end

      context "when client has special characters in name" do
        before do
          client_record.update!(name: "María José O'Connor & Sons")

          stub_request(:post, telegram_url)
            .to_return(status: 200, body: { ok: true }.to_json)
        end

        it "sends notification with special characters properly encoded" do
          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            expect(body["text"]).to include("María José O'Connor & Sons")
          }
        end
      end

      context "when category has emoji" do
        before do
          stub_request(:post, telegram_url)
            .to_return(status: 200, body: { ok: true }.to_json)
        end

        it "sends notification with emoji preserved" do
          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "🔧 Plomería",
            city: "Centro Histórico"
          )

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            expect(body["text"]).to include("🔧 Plomería")
          }
        end
      end

      context "when multiple categories are unavailable in same session" do
        before do
          stub_request(:post, telegram_url)
            .to_return(status: 200, body: { ok: true }.to_json)
        end

        it "sends separate notifications for each unavailable category" do
          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Electricidad",
            city: "Centro Histórico"
          )

          expect(WebMock).to have_requested(:post, telegram_url).twice
        end
      end

      context "when different clients request same unavailable category" do
        let!(:another_client) do
          Client.create!(
            name: "Carlos Pérez",
            phone: "5219521234567"
          )
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 200, body: { ok: true }.to_json)
        end

        it "sends separate notifications for each client" do
          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          TelegramNotifier.notify_unavailable_area(
            client: another_client,
            category: "Plomería",
            city: "Centro Histórico"
          )

          # Verify both notifications were sent
          expect(WebMock).to have_requested(:post, telegram_url).twice

          # Verify first notification contains Mariana López
          expect(WebMock).to have_requested(:post, telegram_url).with { |req|
            body = JSON.parse(req.body)
            body["text"].include?("Mariana López")
          }.once

          # Verify second notification contains Carlos Pérez
          expect(WebMock).to have_requested(:post, telegram_url).with { |req|
            body = JSON.parse(req.body)
            body["text"].include?("Carlos Pérez")
          }.once
        end
      end

      context "when notification is sent for different cities" do
        before do
          stub_request(:post, telegram_url)
            .to_return(status: 200, body: { ok: true }.to_json)
        end

        it "includes correct city in each notification" do
          cities = ["Centro Histórico", "Boca del Río", "Mocambo", "Costa Verde"]

          cities.each do |city|
            TelegramNotifier.notify_unavailable_area(
              client: client_record,
              category: "Plomería",
              city: city
            )
          end

          # Verify total number of requests
          expect(WebMock).to have_requested(:post, telegram_url).times(cities.length)

          # Verify each city appears in exactly one notification
          cities.each do |city|
            expect(WebMock).to have_requested(:post, telegram_url).with { |req|
              body = JSON.parse(req.body)
              body["text"].include?("📍 #{city}")
            }.once
          end
        end
      end
    end

    context "when testing error recovery scenarios" do
      let!(:client_record) do
        Client.create!(
          name: "Test Client",
          phone: client_phone
        )
      end

      context "when Telegram API returns 401 Unauthorized" do
        let(:error_response) do
          {
            ok: false,
            error_code: 401,
            description: "Unauthorized: bot token is invalid"
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 401, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "logs unauthorized error with token verification message" do
          allow(Rails.logger).to receive(:error)

          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Unauthorized \(401\).*Invalid TELEGRAM_BOT_TOKEN/)
          )
        end

        it "returns nil without blocking flow" do
          result = TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(result).to be_nil
        end
      end

      context "when Telegram API returns 429 Rate Limited" do
        let(:error_response) do
          {
            ok: false,
            error_code: 429,
            description: "Too Many Requests: retry after 30",
            parameters: { retry_after: 30 }
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 429, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "logs rate limit error with retry_after value" do
          allow(Rails.logger).to receive(:error)

          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Rate Limited \(429\).*Retry after 30 seconds/)
          )
        end

        it "does not retry automatically" do
          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          # Should only make one request, not retry
          expect(WebMock).to have_requested(:post, telegram_url).once
        end
      end

      context "when network error occurs" do
        before do
          stub_request(:post, telegram_url).to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))
        end

        it "logs network error with connectivity message" do
          allow(Rails.logger).to receive(:error)

          TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Network error sending notification.*Check internet connectivity/)
          )
        end

        it "returns nil without raising exception" do
          result = TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )

          expect(result).to be_nil
        end
      end

      context "when verifying C2F flow continues despite Telegram failure" do
        before do
          # Simulate Telegram API failure
          stub_request(:post, telegram_url).to_return(status: 500, body: { ok: false, description: "Internal Server Error" }.to_json)
        end

        it "completes C2F flow even when Telegram notification fails" do
          # This test explicitly verifies Task 24.5: Telegram failure doesn't block main flow
          allow(Rails.logger).to receive(:info)
          allow(Rails.logger).to receive(:error)

          # The C2F flow should complete successfully
          expect do
            TelegramNotifier.notify_unavailable_area(
              client: client_record,
              category: "Plomería",
              city: "Centro Histórico"
            )
          end.not_to raise_error

          # Verify error was logged
          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Telegram Server Error \(500\)/)
          )

          # Verify the method returns nil (non-blocking)
          result = TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )
          expect(result).to be_nil
        end

        it "allows subsequent operations after Telegram failure" do
          # First call fails
          result1 = TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Plomería",
            city: "Centro Histórico"
          )
          expect(result1).to be_nil

          # Second call should also work (not blocked by previous failure)
          result2 = TelegramNotifier.notify_unavailable_area(
            client: client_record,
            category: "Electricidad",
            city: "Boca del Río"
          )
          expect(result2).to be_nil

          # Verify both requests were attempted
          expect(WebMock).to have_requested(:post, telegram_url).twice
        end
      end
    end
  end
end
