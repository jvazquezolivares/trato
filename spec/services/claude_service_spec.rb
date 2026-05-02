# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClaudeService do
  let(:system_prompt) { "You are a helpful assistant." }
  let(:user_message) { "Terminé un trabajo con los Martínez" }
  let(:context) { {} }

  let(:valid_response_body) do
    {
      "message" => "Registrado ✅ ¿Cuánto te pagaron?",
      "action" => "register_job",
      "action_data" => { "client_name" => "Martínez" },
      "new_stage" => "collecting_info",
      "updated_context" => { "pending_field" => "amount" },
      "should_save_message" => true,
      "intent" => "job_registered"
    }
  end

  let(:api_response) do
    { "content" => [ { "text" => valid_response_body.to_json } ] }
  end

  let(:messages_double) { instance_double(Anthropic::Api::Messages) }

  before do
    allow(Anthropic).to receive(:messages).and_return(messages_double)
  end

  describe ".call" do
    context "when Claude returns a valid JSON response" do
      before do
        allow(messages_double).to receive(:create).and_return(api_response)
      end

      it "returns a parsed hash with all expected keys" do
        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message,
          context: context
        )

        expect(result).to be_a(Hash)
        expect(result["message"]).to eq("Registrado ✅ ¿Cuánto te pagaron?")
        expect(result["action"]).to eq("register_job")
        expect(result["action_data"]).to eq({ "client_name" => "Martínez" })
        expect(result["new_stage"]).to eq("collecting_info")
        expect(result["should_save_message"]).to be(true)
        expect(result["intent"]).to eq("job_registered")
      end

      it "sends the correct model identifier to the API" do
        described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(messages_double).to have_received(:create).with(
          hash_including(model: "claude-haiku-4-5-20251001")
        )
      end

      it "sends the sonnet model when specified" do
        described_class.call(
          model: :sonnet,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(messages_double).to have_received(:create).with(
          hash_including(model: "claude-sonnet-4-6")
        )
      end
    end

    context "when building messages with conversation history" do
      let(:history_context) do
        {
          "history" => [
            { "role" => "user", "content" => "Hola" },
            { "role" => "assistant", "content" => "¡Hola! ¿Cómo te fue hoy?" }
          ]
        }
      end

      before do
        allow(messages_double).to receive(:create).and_return(api_response)
      end

      it "includes prior history and appends the new user message" do
        described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message,
          context: history_context
        )

        expect(messages_double).to have_received(:create).with(
          hash_including(
            messages: [
              { role: "user", content: "Hola" },
              { role: "assistant", content: "¡Hola! ¿Cómo te fue hoy?" },
              { role: "user", content: user_message }
            ]
          )
        )
      end
    end

    context "when context has no history" do
      before do
        allow(messages_double).to receive(:create).and_return(api_response)
      end

      it "sends only the current user message" do
        described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message,
          context: { "stage" => "active" }
        )

        expect(messages_double).to have_received(:create).with(
          hash_including(
            messages: [ { role: "user", content: user_message } ]
          )
        )
      end
    end

    context "when Claude returns malformed JSON" do
      let(:bad_response) do
        { "content" => [ { "text" => "This is not JSON at all" } ] }
      end

      before do
        allow(messages_double).to receive(:create).and_return(bad_response)
        allow(Rails.logger).to receive(:error)
      end

      it "returns the safe fallback response" do
        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Lo siento, tuve un problema. ¿Puedes repetir eso?")
        expect(result["action"]).to eq("none")
        expect(result["should_save_message"]).to be(false)
      end

      it "logs the parse failure" do
        described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(Rails.logger).to have_received(:error).with(/JSON parse failure/)
      end
    end

    context "when Claude returns JSON wrapped in markdown code blocks" do
      let(:markdown_response) do
        json_content = valid_response_body.to_json
        wrapped_text = "```json\n#{json_content}\n```"
        { "content" => [ { "text" => wrapped_text } ] }
      end

      before do
        allow(messages_double).to receive(:create).and_return(markdown_response)
      end

      it "strips the markdown and parses the JSON correctly" do
        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Registrado ✅ ¿Cuánto te pagaron?")
        expect(result["action"]).to eq("register_job")
        expect(result["should_save_message"]).to be(true)
      end

      it "handles code blocks without language specifier" do
        json_content = valid_response_body.to_json
        wrapped_text = "```\n#{json_content}\n```"
        response = { "content" => [ { "text" => wrapped_text } ] }

        allow(messages_double).to receive(:create).and_return(response)

        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Registrado ✅ ¿Cuánto te pagaron?")
      end
    end

    context "when Claude returns a non-object JSON (e.g. array)" do
      let(:array_response) do
        { "content" => [ { "text" => "[1, 2, 3]" } ] }
      end

      before do
        allow(messages_double).to receive(:create).and_return(array_response)
        allow(Rails.logger).to receive(:warn)
      end

      it "returns the safe fallback response" do
        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Lo siento, tuve un problema. ¿Puedes repetir eso?")
      end
    end

    context "when sonnet is unavailable and falls back to haiku" do
      before do
        call_count = 0
        allow(messages_double).to receive(:create) do |**params|
          call_count += 1
          if call_count == 1 && params[:model] == "claude-sonnet-4-6"
            raise Anthropic::Client::ApiError, "Service unavailable"
          end

          api_response
        end
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:info)
      end

      it "retries with haiku and returns a valid response" do
        result = described_class.call(
          model: :sonnet,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Registrado ✅ ¿Cuánto te pagaron?")
      end

      it "logs the fallback" do
        described_class.call(
          model: :sonnet,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(Rails.logger).to have_received(:info).with(/Falling back from sonnet to haiku/)
      end
    end

    context "when haiku also fails" do
      before do
        allow(messages_double).to receive(:create)
          .and_raise(Anthropic::Client::ApiError, "Service unavailable")
        allow(Rails.logger).to receive(:error)
      end

      it "returns the safe fallback without infinite retry" do
        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Lo siento, tuve un problema. ¿Puedes repetir eso?")
        expect(result["action"]).to eq("none")
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(messages_double).to receive(:create)
          .and_raise(StandardError, "Something went wrong")
        allow(Rails.logger).to receive(:error)
      end

      it "returns the safe fallback" do
        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Lo siento, tuve un problema. ¿Puedes repetir eso?")
      end

      it "logs the unexpected error" do
        described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(Rails.logger).to have_received(:error).with(/Unexpected error/)
      end
    end

    context "when response has partial keys" do
      let(:partial_response) do
        { "content" => [ { "text" => '{"message": "Hola", "action": "none"}' } ] }
      end

      before do
        allow(messages_double).to receive(:create).and_return(partial_response)
      end

      it "fills missing keys with safe defaults" do
        result = described_class.call(
          model: :haiku,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Hola")
        expect(result["action"]).to eq("none")
        expect(result["should_save_message"]).to be(false)
        expect(result["intent"]).to be_nil
        expect(result["action_data"]).to eq({})
      end
    end

    context "when rate limited on sonnet" do
      before do
        call_count = 0
        allow(messages_double).to receive(:create) do |**params|
          call_count += 1
          if call_count == 1 && params[:model] == "claude-sonnet-4-6"
            raise Anthropic::Client::RateLimitError, "Rate limited"
          end

          api_response
        end
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:info)
      end

      it "falls back to haiku" do
        result = described_class.call(
          model: :sonnet,
          system_prompt: system_prompt,
          user_message: user_message
        )

        expect(result["message"]).to eq("Registrado ✅ ¿Cuánto te pagaron?")
      end
    end
  end

  describe "MODELS" do
    it "maps haiku to the correct model identifier" do
      expect(ClaudeService::MODELS[:haiku]).to eq("claude-haiku-4-5-20251001")
    end

    it "maps sonnet to the correct model identifier" do
      expect(ClaudeService::MODELS[:sonnet]).to eq("claude-sonnet-4-6")
    end
  end

  describe "SAFE_FALLBACK" do
    it "is frozen to prevent accidental mutation" do
      expect(ClaudeService::SAFE_FALLBACK).to be_frozen
    end

    it "contains all required response keys" do
      expected_keys = %w[message action action_data new_stage updated_context should_save_message intent]
      expect(ClaudeService::SAFE_FALLBACK.keys).to match_array(expected_keys)
    end
  end
end
