# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientMessageJob, type: :job do
  describe "#perform" do
    let(:from) { "5212219876543" }
    let(:body) { "Hola, necesito un plomero" }
    let(:media_url) { nil }

    before do
      # Stub ClientAssistantOrchestrator to avoid actual processing
      allow(ClientAssistantOrchestrator).to receive(:call)
      allow(ClientAssistantOrchestrator).to receive(:call_search_mode)
    end

    context "when message contains a valid short_uuid" do
      let(:body) { "Hola, mi código es abc12345" }
      let(:short_uuid) { "abc12345" }
      let(:provider) { instance_double(Provider, short_uuid: short_uuid) }

      before do
        allow(Provider).to receive(:find_by).with(short_uuid: short_uuid).and_return(provider)
      end

      it "calls ClientAssistantOrchestrator with provider" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).to have_received(:call).with(
          provider: provider,
          from: from,
          body: body
        )
      end

      it "does not call search mode" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).not_to have_received(:call_search_mode)
      end
    end

    context "when message contains an invalid short_uuid" do
      let(:body) { "Hola, mi código es invalid1" }

      before do
        allow(Rails.logger).to receive(:warn)
      end

      it "calls search mode (no valid hex short_uuid extracted)" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).to have_received(:call_search_mode).with(
          from: from,
          body: body
        )
      end

      it "does not call regular ClientAssistantOrchestrator" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).not_to have_received(:call)
      end
    end

    context "when message contains a short_uuid that doesn't match any provider" do
      let(:body) { "Hola, mi código es abc12345" }
      let(:short_uuid) { "abc12345" }

      before do
        allow(Provider).to receive(:find_by).with(short_uuid: short_uuid).and_return(nil)
        allow(Rails.logger).to receive(:warn)
      end

      it "logs a warning" do
        described_class.new.perform(from, body, media_url)

        expect(Rails.logger).to have_received(:warn).with("[ClientMessageJob] Invalid short_uuid: #{short_uuid}")
      end

      it "does not call ClientAssistantOrchestrator" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).not_to have_received(:call)
        expect(ClientAssistantOrchestrator).not_to have_received(:call_search_mode)
      end
    end

    context "when message does not contain a short_uuid" do
      let(:body) { "Hola, necesito un plomero" }

      it "calls ClientAssistantOrchestrator in search mode" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).to have_received(:call_search_mode).with(
          from: from,
          body: body
        )
      end

      it "does not call regular ClientAssistantOrchestrator" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).not_to have_received(:call)
      end
    end

    context "when body is blank" do
      let(:body) { "" }

      it "calls search mode (no short_uuid extracted)" do
        described_class.new.perform(from, body, media_url)

        expect(ClientAssistantOrchestrator).to have_received(:call_search_mode).with(
          from: from,
          body: body
        )
      end
    end

    describe "#extract_short_uuid" do
      let(:job) { described_class.new }

      it "extracts 8-character hexadecimal string" do
        result = job.send(:extract_short_uuid, "Mi código es abc12345 por favor")
        expect(result).to eq("abc12345")
      end

      it "returns nil when no short_uuid present" do
        result = job.send(:extract_short_uuid, "Hola, necesito ayuda")
        expect(result).to be_nil
      end

      it "returns nil when body is blank" do
        result = job.send(:extract_short_uuid, "")
        expect(result).to be_nil
      end

      it "extracts lowercase version of uppercase short_uuid" do
        result = job.send(:extract_short_uuid, "Código ABC12345")
        expect(result).to eq("abc12345")
      end

      it "does not extract strings longer than 8 characters" do
        result = job.send(:extract_short_uuid, "abc123456")
        expect(result).to be_nil
      end

      it "does not extract strings shorter than 8 characters" do
        result = job.send(:extract_short_uuid, "abc1234")
        expect(result).to be_nil
      end
    end
  end
end
