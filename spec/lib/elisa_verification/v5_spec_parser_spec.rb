# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::V5SpecParser do
  let(:spec_file_path) { Rails.root.join("../KIRO_PROMPT_FLOWS_v5.md").to_s }
  let(:parser) { described_class.new(spec_file_path) }

  describe "#initialize" do
    context "with valid file path" do
      it "creates a new parser instance" do
        expect(parser).to be_a(described_class)
        expect(parser.spec_file_path).to eq(spec_file_path)
      end
    end

    context "with nil file path" do
      it "raises ArgumentError" do
        expect { described_class.new(nil) }.to raise_error(ArgumentError, /cannot be nil or empty/)
      end
    end

    context "with empty file path" do
      it "raises ArgumentError" do
        expect { described_class.new("") }.to raise_error(ArgumentError, /cannot be nil or empty/)
      end
    end

    context "with non-existent file" do
      it "raises Errno::ENOENT" do
        expect { described_class.new("/nonexistent/file.md") }.to raise_error(Errno::ENOENT)
      end
    end
  end

  describe "#parse" do
    let(:messages) { parser.parse }

    it "returns a hash of messages" do
      expect(messages).to be_a(Hash)
      expect(messages).not_to be_empty
    end

    it "extracts messages with flow IDs as keys" do
      # Should have keys like "P1B", "C5A", etc.
      flow_id_pattern = /^[A-Z]\d+[A-Z]?/
      matching_keys = messages.keys.select { |k| k.match?(flow_id_pattern) }
      expect(matching_keys).not_to be_empty
    end

    it "creates MessageReference objects as values" do
      messages.each_value do |message|
        expect(message).to be_a(ElisaVerification::Models::MessageReference)
      end
    end

    context "P1B decline flow messages" do
      it "extracts the decline closing message" do
        # Look for P1B messages
        p1b_messages = messages.select { |k, _v| k.start_with?("P1B") }
        expect(p1b_messages).not_to be_empty

        # Check if any P1B message contains the expected text
        decline_message = p1b_messages.values.find do |msg|
          msg.text.include?("Gracias por contarme") && msg.text.include?("Elisa")
        end

        expect(decline_message).not_to be_nil
        expect(decline_message.flow_id).to eq("P1B")
      end

      it "extracts the decline reasons list" do
        # The list may be extracted as a code block or list message
        p1b_messages = messages.select { |k, _v| k.start_with?("P1B") }

        # Find message containing the list title
        list_message = p1b_messages.values.find do |msg|
          msg.text.include?("¿Por qué no por ahora?") &&
            (msg.text.include?("Estoy muy ocupado") || msg.text.include?("Options"))
        end

        expect(list_message).not_to be_nil
      end
    end

    context "C5A emergency messages" do
      it "extracts emergency alert messages" do
        c5a_messages = messages.select { |k, _v| k.start_with?("C5A") }
        expect(c5a_messages).not_to be_empty

        # Should have messages with emergency indicators
        emergency_message = c5a_messages.values.find { |msg| msg.text.include?("🚨") }
        expect(emergency_message).not_to be_nil
      end

      it "extracts interpolation variables from C5A messages" do
        c5a_messages = messages.select { |k, _v| k.start_with?("C5A") }

        # Find message with interpolation variables
        message_with_vars = c5a_messages.values.find { |msg| !msg.interpolation_vars.empty? }
        expect(message_with_vars).not_to be_nil
        expect(message_with_vars.interpolation_vars).to be_an(Array)
      end
    end

    context "List Messages" do
      it "extracts List Message structures" do
        list_messages = messages.select { |k, _v| k.include?("list") }
        expect(list_messages).not_to be_empty

        list_messages.each_value do |msg|
          expect(msg.context).to include("List Message")
        end
      end

      it "stores List Messages as JSON" do
        list_messages = messages.select { |k, _v| k.include?("list") }

        list_messages.each_value do |msg|
          expect { JSON.parse(msg.text) }.not_to raise_error
          parsed = JSON.parse(msg.text)
          expect(parsed).to have_key("title")
          expect(parsed).to have_key("options")
        end
      end
    end
  end

  describe "#message_for" do
    before { parser.parse }

    context "with existing flow ID" do
      it "returns the message reference" do
        # Try to get a P1B message (we know this exists)
        p1b_keys = parser.messages.keys.select { |k| k.start_with?("P1B") }
        expect(p1b_keys).not_to be_empty

        message = parser.message_for(p1b_keys.first)
        expect(message).to be_a(ElisaVerification::Models::MessageReference)
        expect(message.flow_id).to eq("P1B")
      end
    end

    context "with non-existent flow ID" do
      it "returns nil" do
        message = parser.message_for("NONEXISTENT")
        expect(message).to be_nil
      end
    end
  end

  describe "message extraction" do
    before { parser.parse }

    it "converts placeholder syntax to Rails I18n syntax" do
      messages_with_vars = parser.messages.values.select { |msg| !msg.interpolation_vars.empty? }
      expect(messages_with_vars).not_to be_empty

      messages_with_vars.each do |msg|
        # Should use %{var} syntax, not [var] syntax
        expect(msg.text).not_to match(/\[[\w\s]+\]/)
        expect(msg.text).to match(/%\{[\w_]+\}/) if msg.interpolation_vars.any?
      end
    end

    it "normalizes variable names correctly" do
      messages_with_vars = parser.messages.values.select { |msg| !msg.interpolation_vars.empty? }

      messages_with_vars.each do |msg|
        # Variable names should be simple: name, phone, provider_name, etc.
        msg.interpolation_vars.each do |var|
          expect(var).to match(/^[a-z_]+$/)
          expect(var).not_to include(" ")
        end
      end
    end

    it "preserves emojis in message text" do
      emoji_messages = parser.messages.values.select { |msg| msg.text.match?(/[\u{1F300}-\u{1F9FF}]/) }
      expect(emoji_messages).not_to be_empty

      emoji_messages.each do |msg|
        # Message should contain emoji characters
        expect(msg.text.encoding).to eq(Encoding::UTF_8)
      end
    end

    it "preserves Spanish characters" do
      spanish_messages = parser.messages.values.select { |msg| msg.text.match?(/[¡¿ñáéíóúÁÉÍÓÚ]/) }
      expect(spanish_messages).not_to be_empty

      spanish_messages.each do |msg|
        expect(msg.text.encoding).to eq(Encoding::UTF_8)
      end
    end
  end
end
