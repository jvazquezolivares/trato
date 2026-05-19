# frozen_string_literal: true

require "rails_helper"
require "webmock/rspec"

RSpec.describe TelegramNotifier do
  include ActiveSupport::Testing::TimeHelpers
  let(:client) do
    instance_double(
      Client,
      name: "Mariana López",
      phone: "+521234567890"
    )
  end
  let(:category) { "Plomería" }
  let(:city) { "Veracruz" }
  let(:bot_token) { "123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11" }
  let(:chat_id) { "-1001234567890" }
  let(:telegram_url) { "https://api.telegram.org/bot#{bot_token}/sendMessage" }

  before do
    # Set environment variables for tests
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(bot_token)
    allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(chat_id)

    # Freeze time for consistent timestamp testing
    travel_to Time.zone.local(2026, 5, 19, 14, 30, 0)
  end

  after do
    travel_back
  end

  describe ".notify_unavailable_area" do
    context "when Telegram is properly configured" do
      context "when API request succeeds" do
        let(:success_response) do
          {
            ok: true,
            result: {
              message_id: 123,
              chat: { id: chat_id.to_i, type: "group" },
              date: 1716127800,
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

        it "sends notification with correct message format" do
          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(WebMock).to have_requested(:post, telegram_url) { |req|
            body = JSON.parse(req.body)
            expect(body["chat_id"]).to eq(chat_id)
            expect(body["text"]).to include("🔔 Nueva solicitud sin técnico")
            expect(body["text"]).to include("👤 Mariana López")
            expect(body["text"]).to include("📱 +521234567890")
            expect(body["text"]).to include("🔧 Plomería")
            expect(body["text"]).to include("📍 Veracruz")
            expect(body["text"]).to include("⏰ 19/05/2026 14:30")
          }
        end

        it "logs success message" do
          allow(Rails.logger).to receive(:info)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:info).with("[TelegramNotifier] Notification sent successfully")
        end

        it "returns the HTTP response" do
          result = described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(result).to be_a(Net::HTTPSuccess)
        end
      end

      context "when API returns 400 Bad Request" do
        let(:error_response) do
          {
            ok: false,
            error_code: 400,
            description: "Bad Request: chat not found"
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 400, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "logs error with details" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Bad Request \(400\): Bad Request: chat not found/)
          )
        end

        it "returns nil without raising exception" do
          expect do
            result = described_class.notify_unavailable_area(client: client, category: category, city: city)
            expect(result).to be_nil
          end.not_to raise_error
        end
      end

      context "when API returns 401 Unauthorized" do
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

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Unauthorized \(401\).*Invalid TELEGRAM_BOT_TOKEN/)
          )
        end

        it "returns nil" do
          result = described_class.notify_unavailable_area(client: client, category: category, city: city)
          expect(result).to be_nil
        end
      end

      context "when API returns 403 Forbidden" do
        let(:error_response) do
          {
            ok: false,
            error_code: 403,
            description: "Forbidden: bot was blocked by the user"
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 403, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "logs forbidden error with permissions message" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Forbidden \(403\).*Bot may be blocked by user/)
          )
        end
      end

      context "when API returns 404 Not Found" do
        let(:error_response) do
          {
            ok: false,
            error_code: 404,
            description: "Not Found"
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 404, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "logs not found error" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Not Found \(404\)/)
          )
        end
      end

      context "when API returns 429 Rate Limited" do
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

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Rate Limited \(429\).*Retry after 30 seconds/)
          )
        end
      end

      context "when API returns 500 Server Error" do
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

        it "logs server error" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Telegram Server Error \(500\)/)
          )
        end
      end

      context "when API returns unexpected status code" do
        let(:error_response) do
          {
            ok: false,
            error_code: 418,
            description: "I'm a teapot"
          }.to_json
        end

        before do
          stub_request(:post, telegram_url)
            .to_return(status: 418, body: error_response, headers: { "Content-Type" => "application/json" })
        end

        it "logs unexpected error with status code" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Unexpected HTTP 418/)
          )
        end
      end

      context "when API response body is not valid JSON" do
        before do
          stub_request(:post, telegram_url)
            .to_return(status: 500, body: "Internal Server Error", headers: { "Content-Type" => "text/html" })
        end

        it "handles parse error gracefully" do
          allow(Rails.logger).to receive(:error)

          expect do
            described_class.notify_unavailable_area(client: client, category: category, city: city)
          end.not_to raise_error

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Telegram Server Error \(500\)/)
          )
        end
      end

      context "when network timeout occurs" do
        before do
          stub_request(:post, telegram_url).to_timeout
        end

        it "logs timeout error" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Timeout sending notification/)
          )
        end

        it "returns nil without raising exception" do
          result = described_class.notify_unavailable_area(client: client, category: category, city: city)
          expect(result).to be_nil
        end
      end

      context "when socket error occurs" do
        before do
          stub_request(:post, telegram_url).to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))
        end

        it "logs network error" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Network error sending notification.*Check internet connectivity/)
          )
        end

        it "returns nil" do
          result = described_class.notify_unavailable_area(client: client, category: category, city: city)
          expect(result).to be_nil
        end
      end

      context "when unexpected exception occurs" do
        before do
          stub_request(:post, telegram_url).to_raise(StandardError.new("Something went wrong"))
        end

        it "logs unexpected error with backtrace" do
          allow(Rails.logger).to receive(:error)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:error).with(
            a_string_matching(/Unexpected error sending notification: StandardError — Something went wrong/)
          )
        end

        it "returns nil" do
          result = described_class.notify_unavailable_area(client: client, category: category, city: city)
          expect(result).to be_nil
        end
      end
    end

    context "when Telegram is not configured" do
      context "when TELEGRAM_BOT_TOKEN is missing" do
        before do
          allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(nil)
          allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(chat_id)
        end

        it "logs warning and skips notification" do
          allow(Rails.logger).to receive(:warn)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:warn).with(
            a_string_matching(/Telegram not configured.*Missing TELEGRAM_BOT_TOKEN/)
          )
        end

        it "does not make HTTP request" do
          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(WebMock).not_to have_requested(:post, /api\.telegram\.org/)
        end

        it "returns nil" do
          result = described_class.notify_unavailable_area(client: client, category: category, city: city)
          expect(result).to be_nil
        end
      end

      context "when TELEGRAM_CHAT_ID is missing" do
        before do
          allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(bot_token)
          allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(nil)
        end

        it "logs warning and skips notification" do
          allow(Rails.logger).to receive(:warn)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:warn).with(
            a_string_matching(/Telegram not configured.*Missing.*TELEGRAM_CHAT_ID/)
          )
        end

        it "does not make HTTP request" do
          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(WebMock).not_to have_requested(:post, /api\.telegram\.org/)
        end
      end

      context "when both credentials are missing" do
        before do
          allow(ENV).to receive(:[]).with("TELEGRAM_BOT_TOKEN").and_return(nil)
          allow(ENV).to receive(:[]).with("TELEGRAM_CHAT_ID").and_return(nil)
        end

        it "logs warning" do
          allow(Rails.logger).to receive(:warn)

          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(Rails.logger).to have_received(:warn)
        end

        it "does not make HTTP request" do
          described_class.notify_unavailable_area(client: client, category: category, city: city)

          expect(WebMock).not_to have_requested(:post, /api\.telegram\.org/)
        end
      end
    end

    context "when client has special characters in name" do
      let(:client) do
        instance_double(
          Client,
          name: "María José O'Connor & Sons",
          phone: "+521234567890"
        )
      end

      before do
        stub_request(:post, telegram_url)
          .to_return(status: 200, body: { ok: true }.to_json)
      end

      it "sends notification with special characters properly encoded" do
        described_class.notify_unavailable_area(client: client, category: category, city: city)

        expect(WebMock).to have_requested(:post, telegram_url) { |req|
          body = JSON.parse(req.body)
          expect(body["text"]).to include("María José O'Connor & Sons")
        }
      end
    end

    context "when category has emoji" do
      let(:category) { "🔧 Plomería" }

      before do
        stub_request(:post, telegram_url)
          .to_return(status: 200, body: { ok: true }.to_json)
      end

      it "sends notification with emoji preserved" do
        described_class.notify_unavailable_area(client: client, category: category, city: city)

        expect(WebMock).to have_requested(:post, telegram_url) { |req|
          body = JSON.parse(req.body)
          expect(body["text"]).to include("🔧 Plomería")
        }
      end
    end
  end

  describe ".build_message (private method behavior)" do
    let(:expected_timestamp) { "19/05/2026 14:30" }

    it "includes all required fields in correct format" do
      # We test this indirectly through notify_unavailable_area
      stub_request(:post, telegram_url)
        .to_return(status: 200, body: { ok: true }.to_json)

      described_class.notify_unavailable_area(client: client, category: category, city: city)

      expect(WebMock).to have_requested(:post, telegram_url) { |req|
        body = JSON.parse(req.body)
        text = body["text"]

        # Verify structure and order
        lines = text.split("\n")
        expect(lines[0]).to eq("🔔 Nueva solicitud sin técnico")
        expect(lines[1]).to eq("👤 Mariana López")
        expect(lines[2]).to eq("📱 +521234567890")
        expect(lines[3]).to eq("🔧 Plomería")
        expect(lines[4]).to eq("📍 Veracruz")
        expect(lines[5]).to eq("⏰ #{expected_timestamp}")
      }
    end
  end
end
