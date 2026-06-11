# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::Models::MessageReference do
  describe "#initialize" do
    context "with valid parameters" do
      it "creates a MessageReference with all attributes" do
        message_ref = described_class.new(
          flow_id: "P1B",
          text: "¡Gracias por contarme! 😊",
          interpolation_vars: ["name"],
          context: "Decline closing message"
        )

        expect(message_ref.flow_id).to eq("P1B")
        expect(message_ref.text).to eq("¡Gracias por contarme! 😊")
        expect(message_ref.interpolation_vars).to eq(["name"])
        expect(message_ref.context).to eq("Decline closing message")
      end

      it "creates a MessageReference with empty interpolation vars" do
        message_ref = described_class.new(
          flow_id: "P1A",
          text: "¡Hola! 👋",
          interpolation_vars: [],
          context: "Welcome message"
        )

        expect(message_ref.interpolation_vars).to eq([])
      end

      it "creates a MessageReference with nil interpolation vars (converts to empty array)" do
        message_ref = described_class.new(
          flow_id: "P1A",
          text: "¡Hola! 👋",
          interpolation_vars: nil,
          context: "Welcome message"
        )

        expect(message_ref.interpolation_vars).to eq([])
      end

      it "creates a MessageReference with nil context (converts to empty string)" do
        message_ref = described_class.new(
          flow_id: "P1A",
          text: "¡Hola! 👋",
          interpolation_vars: [],
          context: nil
        )

        expect(message_ref.context).to eq("")
      end
    end

    context "with invalid parameters" do
      it "raises ArgumentError when flow_id is nil" do
        expect do
          described_class.new(
            flow_id: nil,
            text: "Some text",
            interpolation_vars: [],
            context: "Context"
          )
        end.to raise_error(ArgumentError, "flow_id cannot be nil or empty")
      end

      it "raises ArgumentError when flow_id is empty" do
        expect do
          described_class.new(
            flow_id: "",
            text: "Some text",
            interpolation_vars: [],
            context: "Context"
          )
        end.to raise_error(ArgumentError, "flow_id cannot be nil or empty")
      end

      it "raises ArgumentError when text is nil" do
        expect do
          described_class.new(
            flow_id: "P1A",
            text: nil,
            interpolation_vars: [],
            context: "Context"
          )
        end.to raise_error(ArgumentError, "text cannot be nil")
      end
    end

    context "immutability" do
      it "freezes the object after initialization" do
        message_ref = described_class.new(
          flow_id: "P1B",
          text: "Test message",
          interpolation_vars: ["name"],
          context: "Test context"
        )

        expect(message_ref).to be_frozen
      end
    end
  end

  describe "#has_interpolation_variables?" do
    it "returns true when interpolation variables exist" do
      message_ref = described_class.new(
        flow_id: "C5A",
        text: "🚨 %{name}, esto suena urgente.",
        interpolation_vars: ["name", "provider_name", "phone"],
        context: "Emergency alert"
      )

      expect(message_ref.has_interpolation_variables?).to be true
    end

    it "returns false when no interpolation variables exist" do
      message_ref = described_class.new(
        flow_id: "P1A",
        text: "¡Hola! 👋",
        interpolation_vars: [],
        context: "Welcome message"
      )

      expect(message_ref.has_interpolation_variables?).to be false
    end
  end

  describe "#normalized_text" do
    it "normalizes multiple spaces to single space" do
      message_ref = described_class.new(
        flow_id: "P1A",
        text: "¡Hola!    👋   Soy   Elisa",
        interpolation_vars: [],
        context: "Test"
      )

      expect(message_ref.normalized_text).to eq("¡Hola! 👋 Soy Elisa")
    end

    it "strips leading and trailing whitespace" do
      message_ref = described_class.new(
        flow_id: "P1A",
        text: "  ¡Hola! 👋  ",
        interpolation_vars: [],
        context: "Test"
      )

      expect(message_ref.normalized_text).to eq("¡Hola! 👋")
    end

    it "handles newlines and tabs" do
      message_ref = described_class.new(
        flow_id: "P1A",
        text: "¡Hola!\n\t👋",
        interpolation_vars: [],
        context: "Test"
      )

      expect(message_ref.normalized_text).to eq("¡Hola! 👋")
    end
  end

  describe "#==" do
    let(:message_ref1) do
      described_class.new(
        flow_id: "P1B",
        text: "Test message",
        interpolation_vars: ["name"],
        context: "Test context"
      )
    end

    let(:message_ref2) do
      described_class.new(
        flow_id: "P1B",
        text: "Test message",
        interpolation_vars: ["name"],
        context: "Test context"
      )
    end

    let(:different_flow_id) do
      described_class.new(
        flow_id: "P1A",
        text: "Test message",
        interpolation_vars: ["name"],
        context: "Test context"
      )
    end

    let(:different_text) do
      described_class.new(
        flow_id: "P1B",
        text: "Different message",
        interpolation_vars: ["name"],
        context: "Test context"
      )
    end

    it "returns true for identical MessageReferences" do
      expect(message_ref1).to eq(message_ref2)
    end

    it "returns false for different flow_id" do
      expect(message_ref1).not_to eq(different_flow_id)
    end

    it "returns false for different text" do
      expect(message_ref1).not_to eq(different_text)
    end

    it "returns false when comparing with non-MessageReference object" do
      expect(message_ref1).not_to eq("not a message reference")
    end
  end

  describe "#hash" do
    it "returns same hash for identical MessageReferences" do
      message_ref1 = described_class.new(
        flow_id: "P1B",
        text: "Test message",
        interpolation_vars: ["name"],
        context: "Test context"
      )

      message_ref2 = described_class.new(
        flow_id: "P1B",
        text: "Test message",
        interpolation_vars: ["name"],
        context: "Test context"
      )

      expect(message_ref1.hash).to eq(message_ref2.hash)
    end

    it "can be used as hash key" do
      message_ref = described_class.new(
        flow_id: "P1B",
        text: "Test message",
        interpolation_vars: ["name"],
        context: "Test context"
      )

      hash = { message_ref => "some value" }
      expect(hash[message_ref]).to eq("some value")
    end
  end

  describe "#to_s" do
    it "returns a concise string representation" do
      message_ref = described_class.new(
        flow_id: "P1B",
        text: "Test message",
        interpolation_vars: ["name", "phone"],
        context: "Test context"
      )

      expect(message_ref.to_s).to eq('#<MessageReference flow_id=P1B vars=["name", "phone"]>')
    end
  end

  describe "#inspect" do
    it "returns a detailed string representation" do
      message_ref = described_class.new(
        flow_id: "P1B",
        text: "Test message",
        interpolation_vars: ["name"],
        context: "Test context"
      )

      expect(message_ref.inspect).to include("MessageReference")
      expect(message_ref.inspect).to include("flow_id=P1B")
      expect(message_ref.inspect).to include("Test message")
      expect(message_ref.inspect).to include('["name"]')
      expect(message_ref.inspect).to include("Test context")
    end

    it "truncates long text" do
      long_text = "A" * 100
      message_ref = described_class.new(
        flow_id: "P1B",
        text: long_text,
        interpolation_vars: [],
        context: "Test"
      )

      expect(message_ref.inspect).to include("...")
      expect(message_ref.inspect.length).to be < long_text.length + 100
    end

    it "truncates long context" do
      long_context = "B" * 100
      message_ref = described_class.new(
        flow_id: "P1B",
        text: "Test",
        interpolation_vars: [],
        context: long_context
      )

      expect(message_ref.inspect).to include("...")
      expect(message_ref.inspect.length).to be < long_context.length + 100
    end
  end
end
