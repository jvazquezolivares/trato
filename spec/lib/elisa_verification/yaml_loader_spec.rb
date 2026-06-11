# frozen_string_literal: true

require "rails_helper"
require "tempfile"

RSpec.describe ElisaVerification::YamlLoader do
  let(:sample_yaml_content) do
    <<~YAML
      # frozen_string_literal: true

      # Sample YAML file for testing
      es:
        elisa:
          # P1A: Initial welcome message
          provider:
            onboarding:
              # P1A: Welcome message
              welcome: "¡Hola! 👋 Soy Elisa de Trato."

              # P1B: Decline closing message
              decline_closing: "¡Gracias por contarme! 😊"

              # P2A: Name prompt
              name_prompt: "¿Cómo te llamas?"

            # P18: Capabilities
            capabilities:
              intro: "Soy Elisa y te cuento lo que puedo hacer por ti 👇"

          # C2A: Region detection
          client:
            region_detection:
              # C2A: Greeting with detected region
              greeting: "¡Hola! 👋 Soy Elisa de Trato. Veo que eres de %{state}."

            # C7A: Review collection
            review:
              # C7A: Rating acknowledgment
              rating_ack: "¡Gracias por tu calificación de %{rating} ⭐!"

            # List messages
            list_messages:
              # C7A: Star rating
              ratings:
                title: "¿Cómo calificarías el trabajo?"
                body: "Tu opinión ayuda a otros clientes"
                button: "Ver opciones"
                options:
                  - "⭐⭐⭐⭐⭐ Excelente"
                  - "⭐⭐⭐⭐ Muy bueno"
    YAML
  end

  let(:temp_yaml_file) do
    file = Tempfile.new(["test_elisa", ".yml"])
    file.write(sample_yaml_content)
    file.rewind
    file
  end

  after do
    temp_yaml_file.close
    temp_yaml_file.unlink
  end

  describe "#initialize" do
    context "with valid parameters" do
      it "creates a YamlLoader with a file path" do
        loader = described_class.new(temp_yaml_file.path)

        expect(loader.yaml_file_path).to eq(temp_yaml_file.path)
      end
    end

    context "with invalid parameters" do
      it "raises ArgumentError when yaml_file_path is nil" do
        expect do
          described_class.new(nil)
        end.to raise_error(ArgumentError, "yaml_file_path cannot be nil or empty")
      end

      it "raises ArgumentError when yaml_file_path is empty" do
        expect do
          described_class.new("")
        end.to raise_error(ArgumentError, "yaml_file_path cannot be nil or empty")
      end

      it "raises Errno::ENOENT when file does not exist" do
        expect do
          described_class.new("/nonexistent/path/to/file.yml")
        end.to raise_error(Errno::ENOENT, /File not found/)
      end
    end
  end

  describe "#load" do
    let(:loader) { described_class.new(temp_yaml_file.path) }

    it "loads and parses the YAML file" do
      result = loader.load

      expect(result).to be_a(Hash)
      expect(result).to have_key("es")
      expect(result["es"]).to have_key("elisa")
    end

    it "stores the parsed data in the data attribute" do
      loader.load

      expect(loader.data).to be_a(Hash)
      expect(loader.data["es"]["elisa"]["provider"]).to have_key("onboarding")
    end

    it "extracts flow IDs from comments" do
      loader.load

      expect(loader.flow_id_map).not_to be_empty
      expect(loader.flow_id_map).to include("es.elisa.provider.onboarding.welcome" => "P1A")
    end

    context "with invalid YAML syntax" do
      let(:invalid_yaml_file) do
        file = Tempfile.new(["invalid", ".yml"])
        file.write("invalid: yaml: content: [unclosed")
        file.rewind
        file
      end

      after do
        invalid_yaml_file.close
        invalid_yaml_file.unlink
      end

      it "raises YamlParsingError with clear message and context" do
        loader = described_class.new(invalid_yaml_file.path)

        expect { loader.load }.to raise_error(ElisaVerification::YamlParsingError) do |error|
          expect(error.message).to include(invalid_yaml_file.path)
          expect(error.message).to match(/YAML parsing error/)
        end
      end

      it "includes line number in error message when available" do
        loader = described_class.new(invalid_yaml_file.path)

        expect { loader.load }.to raise_error(ElisaVerification::YamlParsingError) do |error|
          # The error message should include line number information
          expect(error.message).to match(/line \d+/) if error.message.include?("line")
        end
      end
    end
  end

  describe "#all_message_keys" do
    let(:loader) { described_class.new(temp_yaml_file.path) }

    context "when YAML is loaded" do
      before { loader.load }

      it "returns all message keys in dot notation" do
        keys = loader.all_message_keys

        expect(keys).to be_an(Array)
        expect(keys).to include("es.elisa.provider.onboarding.welcome")
        expect(keys).to include("es.elisa.provider.onboarding.decline_closing")
        expect(keys).to include("es.elisa.client.region_detection.greeting")
      end

      it "includes nested keys" do
        keys = loader.all_message_keys

        expect(keys).to include("es.elisa.provider.capabilities.intro")
        expect(keys).to include("es.elisa.client.review.rating_ack")
      end

      it "includes List Message structures as single keys" do
        keys = loader.all_message_keys

        # List message should be treated as a single entity
        expect(keys).to include("es.elisa.client.list_messages.ratings")

        # Should not include individual List Message fields as separate keys
        expect(keys).not_to include("es.elisa.client.list_messages.ratings.title")
        expect(keys).not_to include("es.elisa.client.list_messages.ratings.body")
      end

      it "does not return duplicate keys" do
        keys = loader.all_message_keys

        expect(keys.uniq).to eq(keys)
      end
    end

    context "when YAML is not loaded" do
      it "raises RuntimeError" do
        expect do
          loader.all_message_keys
        end.to raise_error(RuntimeError, "YAML file not loaded. Call load() first.")
      end
    end
  end

  describe "#get_message" do
    let(:loader) { described_class.new(temp_yaml_file.path) }

    context "when YAML is loaded" do
      before { loader.load }

      it "returns the message text for a simple string value" do
        message = loader.get_message("es.elisa.provider.onboarding.welcome")

        expect(message).to eq("¡Hola! 👋 Soy Elisa de Trato.")
      end

      it "returns the message text with interpolation variables" do
        message = loader.get_message("es.elisa.client.region_detection.greeting")

        expect(message).to eq("¡Hola! 👋 Soy Elisa de Trato. Veo que eres de %{state}.")
      end

      it "returns a hash for List Message structures" do
        message = loader.get_message("es.elisa.client.list_messages.ratings")

        expect(message).to be_a(Hash)
        expect(message).to have_key("title")
        expect(message).to have_key("body")
        expect(message).to have_key("button")
        expect(message).to have_key("options")
      end

      it "returns an array for List Message options" do
        message = loader.get_message("es.elisa.client.list_messages.ratings")

        expect(message["options"]).to be_an(Array)
        expect(message["options"]).to include("⭐⭐⭐⭐⭐ Excelente")
      end

      it "returns nil for non-existent keys" do
        message = loader.get_message("es.elisa.nonexistent.key")

        expect(message).to be_nil
      end

      it "returns nil for partially matching keys" do
        message = loader.get_message("es.elisa.provider.onboarding.nonexistent")

        expect(message).to be_nil
      end

      it "handles nested hash navigation correctly" do
        message = loader.get_message("es.elisa.provider.capabilities.intro")

        expect(message).to eq("Soy Elisa y te cuento lo que puedo hacer por ti 👇")
      end
    end

    context "when YAML is not loaded" do
      it "raises RuntimeError" do
        expect do
          loader.get_message("es.elisa.provider.onboarding.welcome")
        end.to raise_error(RuntimeError, "YAML file not loaded. Call load() first.")
      end
    end
  end

  describe "#flow_id_for" do
    let(:loader) { described_class.new(temp_yaml_file.path) }

    before { loader.load }

    it "returns the flow ID for a key with a flow ID comment" do
      flow_id = loader.flow_id_for("es.elisa.provider.onboarding.welcome")

      expect(flow_id).to eq("P1A")
    end

    it "returns the flow ID for decline closing message" do
      flow_id = loader.flow_id_for("es.elisa.provider.onboarding.decline_closing")

      expect(flow_id).to eq("P1B")
    end

    it "returns the flow ID for client region detection greeting" do
      flow_id = loader.flow_id_for("es.elisa.client.region_detection.greeting")

      expect(flow_id).to eq("C2A")
    end

    it "returns the flow ID for review rating acknowledgment" do
      flow_id = loader.flow_id_for("es.elisa.client.review.rating_ack")

      expect(flow_id).to eq("C7A")
    end

    it "returns nil for keys without flow ID comments" do
      flow_id = loader.flow_id_for("es.elisa.provider.onboarding.name_prompt")

      expect(flow_id).to eq("P2A")
    end

    it "returns nil for non-existent keys" do
      flow_id = loader.flow_id_for("es.elisa.nonexistent.key")

      expect(flow_id).to be_nil
    end

    it "handles uppercase and lowercase flow IDs" do
      # Flow IDs should be normalized to uppercase
      flow_id = loader.flow_id_for("es.elisa.provider.onboarding.welcome")

      expect(flow_id).to eq("P1A")
      expect(flow_id).not_to eq("p1a")
    end
  end

  describe "private #list_message_structure?" do
    let(:loader) { described_class.new(temp_yaml_file.path) }

    before { loader.load }

    it "identifies List Message structures correctly" do
      message = loader.get_message("es.elisa.client.list_messages.ratings")

      # This is a List Message structure, so it should be returned as a single hash
      expect(message).to be_a(Hash)
      expect(message).to have_key("title")
      expect(message).to have_key("options")
    end

    it "does not treat regular hashes as List Message structures" do
      # The "provider" key contains nested hashes but is not a List Message
      provider = loader.get_message("es.elisa.provider")

      expect(provider).to be_a(Hash)
      expect(provider).to have_key("onboarding")
    end
  end

  describe "integration with actual elisa_es.yml structure" do
    let(:loader) { described_class.new(temp_yaml_file.path) }

    before { loader.load }

    it "correctly extracts all provider onboarding keys" do
      keys = loader.all_message_keys

      provider_keys = keys.select { |k| k.start_with?("es.elisa.provider.onboarding") }

      expect(provider_keys).to include("es.elisa.provider.onboarding.welcome")
      expect(provider_keys).to include("es.elisa.provider.onboarding.decline_closing")
      expect(provider_keys).to include("es.elisa.provider.onboarding.name_prompt")
    end

    it "correctly extracts all client keys" do
      keys = loader.all_message_keys

      client_keys = keys.select { |k| k.start_with?("es.elisa.client") }

      expect(client_keys).to include("es.elisa.client.region_detection.greeting")
      expect(client_keys).to include("es.elisa.client.review.rating_ack")
    end

    it "maintains correct flow ID associations" do
      expect(loader.flow_id_for("es.elisa.provider.onboarding.welcome")).to eq("P1A")
      expect(loader.flow_id_for("es.elisa.provider.onboarding.decline_closing")).to eq("P1B")
      expect(loader.flow_id_for("es.elisa.client.region_detection.greeting")).to eq("C2A")
      expect(loader.flow_id_for("es.elisa.client.review.rating_ack")).to eq("C7A")
    end

    it "handles messages with UTF-8 emojis correctly" do
      message = loader.get_message("es.elisa.provider.onboarding.welcome")

      expect(message).to include("👋")
      expect(message.encoding).to eq(Encoding::UTF_8)
    end

    it "handles messages with interpolation variables correctly" do
      message = loader.get_message("es.elisa.client.region_detection.greeting")

      expect(message).to include("%{state}")
    end
  end
end
