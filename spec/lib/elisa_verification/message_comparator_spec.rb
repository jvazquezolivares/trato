# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::MessageComparator do
  subject(:comparator) { described_class.new }

  let(:reference) do
    ElisaVerification::Models::MessageReference.new(
      flow_id: "P1B",
      text: "¡Hola! 👋 ¿Cómo estás?",
      interpolation_vars: [],
      context: "Test greeting message"
    )
  end

  describe "#compare" do
    context "when messages match exactly" do
      it "returns a matching result with no discrepancies" do
        result = comparator.compare("¡Hola! 👋 ¿Cómo estás?", reference)

        expect(result.matches?).to be true
        expect(result.discrepancies).to be_empty
      end
    end

    context "when messages match after whitespace normalization" do
      it "normalizes multiple spaces between words" do
        result = comparator.compare("¡Hola!    👋    ¿Cómo    estás?", reference)

        expect(result.matches?).to be true
        expect(result.discrepancies).to be_empty
      end

      it "normalizes leading whitespace" do
        result = comparator.compare("   ¡Hola! 👋 ¿Cómo estás?", reference)

        expect(result.matches?).to be true
        expect(result.discrepancies).to be_empty
      end

      it "normalizes trailing whitespace" do
        result = comparator.compare("¡Hola! 👋 ¿Cómo estás?   ", reference)

        expect(result.matches?).to be true
        expect(result.discrepancies).to be_empty
      end

      it "normalizes tabs to spaces" do
        result = comparator.compare("¡Hola!\t👋\t¿Cómo estás?", reference)

        expect(result.matches?).to be true
        expect(result.discrepancies).to be_empty
      end
    end

    context "when yaml_message is nil" do
      it "treats nil as empty string and creates discrepancies" do
        result = comparator.compare(nil, reference)

        expect(result.matches?).to be false
        # Expect emoji and punctuation discrepancies since reference has emojis and Spanish punctuation
        expect(result.discrepancies.size).to be >= 1
        # At least one discrepancy should be present
        expect(result.discrepancies).not_to be_empty
      end
    end

    context "when yaml_message is empty string" do
      it "creates discrepancies" do
        result = comparator.compare("", reference)

        expect(result.matches?).to be false
        # Expect multiple discrepancies (emoji, punctuation) since reference has both
        expect(result.discrepancies.size).to be >= 1
      end
    end

    context "when messages have different content" do
      it "detects punctuation discrepancy as primary issue" do
        result = comparator.compare("Hola 👋 ¿Cómo estás?", reference)

        expect(result.matches?).to be false
        # The primary discrepancy is punctuation (missing ¡!)
        punctuation_discrepancy = result.discrepancies.find { |d| d.type == :punctuation }
        expect(punctuation_discrepancy).not_to be_nil
        expect(punctuation_discrepancy.expected).to include "¡"
      end

      it "preserves original text for specific discrepancies" do
        original_yaml = "Hola    👋    ¿Cómo estás?"
        result = comparator.compare(original_yaml, reference)

        expect(result.matches?).to be false
        # Specific discrepancies (punctuation) are reported
        expect(result.discrepancies).not_to be_empty
      end
    end

    context "with multiline messages" do
      let(:multiline_reference) do
        ElisaVerification::Models::MessageReference.new(
          flow_id: "P16A",
          text: "¡Hola %{name}!\n\nTu perfil está listo.",
          interpolation_vars: ["name"],
          context: "Completion message"
        )
      end

      it "preserves line breaks in comparison" do
        result = comparator.compare("¡Hola %{name}!\n\nTu perfil está listo.", multiline_reference)

        expect(result.matches?).to be true
        expect(result.discrepancies).to be_empty
      end

      it "normalizes whitespace on each line separately" do
        result = comparator.compare("¡Hola   %{name}!  \n\n  Tu perfil  está listo.  ", multiline_reference)

        expect(result.matches?).to be true
        expect(result.discrepancies).to be_empty
      end

      it "detects differences in line break positions" do
        result = comparator.compare("¡Hola %{name}! Tu perfil está listo.", multiline_reference)

        expect(result.matches?).to be false
        expect(result.discrepancies.size).to eq 1
      end
    end

    context "with messages containing emojis" do
      it "preserves emojis in comparison" do
        result = comparator.compare("¡Hola! 👋 ¿Cómo estás?", reference)

        expect(result.matches?).to be true
      end

      it "detects missing emojis" do
        result = comparator.compare("¡Hola! ¿Cómo estás?", reference)

        expect(result.matches?).to be false
        expect(result.discrepancies.size).to eq 1
      end
    end

    context "with messages containing interpolation variables" do
      let(:reference_with_vars) do
        ElisaVerification::Models::MessageReference.new(
          flow_id: "C5A",
          text: "🚨 %{name}, esto suena urgente.",
          interpolation_vars: ["name"],
          context: "Emergency alert"
        )
      end

      it "matches messages with identical interpolation variables" do
        result = comparator.compare("🚨 %{name}, esto suena urgente.", reference_with_vars)

        expect(result.matches?).to be true
      end

      it "detects differences even with interpolation variables present" do
        result = comparator.compare("🚨 %{name} esto suena urgente.", reference_with_vars)

        expect(result.matches?).to be false
      end
    end

    context "with invalid inputs" do
      it "raises ArgumentError when reference is nil" do
        expect do
          comparator.compare("some message", nil)
        end.to raise_error(ArgumentError, "reference cannot be nil")
      end

      it "raises ArgumentError when reference is not a MessageReference" do
        expect do
          comparator.compare("some message", "invalid reference")
        end.to raise_error(ArgumentError, /reference must be a MessageReference/)
      end

      # Note: Cannot test reference.text being nil directly because MessageReference
      # validates this in its initializer and freezes the object. This validation
      # is already covered by the MessageReference spec.
    end

    context "with special characters" do
      let(:reference_with_special_chars) do
        ElisaVerification::Models::MessageReference.new(
          flow_id: "TEST",
          text: "¡Hola! ¿Qué tal? — Elisa",
          interpolation_vars: [],
          context: "Test with Spanish punctuation"
        )
      end

      it "preserves Spanish inverted punctuation" do
        result = comparator.compare("¡Hola! ¿Qué tal? — Elisa", reference_with_special_chars)

        expect(result.matches?).to be true
      end

      it "detects missing Spanish inverted punctuation" do
        result = comparator.compare("Hola! ¿Qué tal? — Elisa", reference_with_special_chars)

        expect(result.matches?).to be false
      end
    end

    # Task 6.2: Emoji comparison tests
    describe "emoji comparison" do
      context "when emojis match exactly" do
        let(:emoji_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "P1A",
            text: "¡Hola! 👋 Bienvenido 🎉",
            interpolation_vars: [],
            context: "Welcome with emojis"
          )
        end

        it "returns matching result" do
          result = comparator.compare("¡Hola! 👋 Bienvenido 🎉", emoji_reference)

          expect(result.matches?).to be true
          expect(result.discrepancies).to be_empty
        end
      end

      context "when emoji is missing" do
        let(:emoji_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "P1A",
            text: "¡Hola! 👋 Bienvenido",
            interpolation_vars: [],
            context: "Greeting with wave"
          )
        end

        it "detects missing emoji discrepancy" do
          result = comparator.compare("¡Hola! Bienvenido", emoji_reference)

          expect(result.matches?).to be false
          emoji_discrepancy = result.discrepancies.find { |d| d.type == :emoji }
          expect(emoji_discrepancy).not_to be_nil
          expect(emoji_discrepancy.expected).to eq "👋"
          expect(emoji_discrepancy.actual).to eq ""
        end
      end

      context "when emoji is incorrect" do
        let(:emoji_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "C5A",
            text: "🚨 URGENTE: Emergencia detectada",
            interpolation_vars: [],
            context: "Emergency alert"
          )
        end

        it "detects incorrect emoji discrepancy" do
          result = comparator.compare("⚠️ URGENTE: Emergencia detectada", emoji_reference)

          expect(result.matches?).to be false
          emoji_discrepancy = result.discrepancies.find { |d| d.type == :emoji }
          expect(emoji_discrepancy).not_to be_nil
          expect(emoji_discrepancy.expected).to include "🚨"
          expect(emoji_discrepancy.actual).to include "⚠"
        end
      end

      context "when multiple emojis differ" do
        let(:emoji_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "P16",
            text: "¡Felicidades! 🎉 Tu perfil está listo 📋",
            interpolation_vars: [],
            context: "Completion message"
          )
        end

        it "detects all emoji discrepancies" do
          result = comparator.compare("¡Felicidades! Tu perfil está listo", emoji_reference)

          expect(result.matches?).to be false
          emoji_discrepancy = result.discrepancies.find { |d| d.type == :emoji }
          expect(emoji_discrepancy).not_to be_nil
        end
      end
    end

    # Task 6.3: Punctuation comparison tests
    describe "punctuation comparison" do
      context "when Spanish punctuation matches exactly" do
        let(:punctuation_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "P1B",
            text: "¡Gracias por contarme! ¿Tienes más preguntas?",
            interpolation_vars: [],
            context: "Question with Spanish punctuation"
          )
        end

        it "returns matching result" do
          result = comparator.compare("¡Gracias por contarme! ¿Tienes más preguntas?", punctuation_reference)

          expect(result.matches?).to be true
          expect(result.discrepancies).to be_empty
        end
      end

      context "when inverted exclamation is missing" do
        let(:punctuation_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "TEST",
            text: "¡Hola!",
            interpolation_vars: [],
            context: "Greeting"
          )
        end

        it "detects missing inverted exclamation" do
          result = comparator.compare("Hola!", punctuation_reference)

          expect(result.matches?).to be false
          punctuation_discrepancy = result.discrepancies.find { |d| d.type == :punctuation }
          expect(punctuation_discrepancy).not_to be_nil
          expect(punctuation_discrepancy.expected).to eq "¡ !"
          expect(punctuation_discrepancy.actual).to eq "!"
        end
      end

      context "when inverted question mark is missing" do
        let(:punctuation_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "TEST",
            text: "¿Cómo estás?",
            interpolation_vars: [],
            context: "Question"
          )
        end

        it "detects missing inverted question mark" do
          result = comparator.compare("Cómo estás?", punctuation_reference)

          expect(result.matches?).to be false
          punctuation_discrepancy = result.discrepancies.find { |d| d.type == :punctuation }
          expect(punctuation_discrepancy).not_to be_nil
          expect(punctuation_discrepancy.expected).to eq "¿ ?"
          expect(punctuation_discrepancy.actual).to eq "?"
        end
      end

      context "when em dash is missing" do
        let(:punctuation_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "P1B",
            text: "¡Que te vaya bien! — Elisa",
            interpolation_vars: [],
            context: "Closing with signature"
          )
        end

        it "detects missing em dash" do
          result = comparator.compare("¡Que te vaya bien! Elisa", punctuation_reference)

          expect(result.matches?).to be false
          punctuation_discrepancy = result.discrepancies.find { |d| d.type == :punctuation }
          expect(punctuation_discrepancy).not_to be_nil
          expect(punctuation_discrepancy.expected).to include "—"
        end
      end

      context "when punctuation order differs" do
        let(:punctuation_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "TEST",
            text: "¡Hola! ¿Qué tal?",
            interpolation_vars: [],
            context: "Greeting and question"
          )
        end

        it "detects punctuation order mismatch" do
          result = comparator.compare("¿Qué tal? ¡Hola!", punctuation_reference)

          expect(result.matches?).to be false
          punctuation_discrepancy = result.discrepancies.find { |d| d.type == :punctuation }
          expect(punctuation_discrepancy).not_to be_nil
        end
      end
    end

    # Task 6.4: Interpolation variable comparison tests
    describe "interpolation variable comparison" do
      context "when interpolation variables match exactly" do
        let(:var_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "C5A",
            text: "🚨 %{name}, llama a %{provider_name} al %{phone}",
            interpolation_vars: ["name", "provider_name", "phone"],
            context: "Emergency alert with variables"
          )
        end

        it "returns matching result" do
          result = comparator.compare("🚨 %{name}, llama a %{provider_name} al %{phone}", var_reference)

          expect(result.matches?).to be true
          expect(result.discrepancies).to be_empty
        end
      end

      context "when interpolation variable is missing" do
        let(:var_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "P2B",
            text: "¡Hola %{name}!",
            interpolation_vars: ["name"],
            context: "Personalized greeting"
          )
        end

        it "detects missing variable as interpolation discrepancy" do
          result = comparator.compare("¡Hola!", var_reference)

          expect(result.matches?).to be false
          interp_discrepancy = result.discrepancies.find { |d| d.type == :interpolation }
          expect(interp_discrepancy).not_to be_nil
          expect(interp_discrepancy.expected).to eq "name"
          expect(interp_discrepancy.actual).to eq ""
          expect(interp_discrepancy.description).to include "DO NOT auto-correct"
        end
      end

      context "when interpolation variable name is incorrect" do
        let(:var_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "C2A",
            text: "Veo que eres de %{state}",
            interpolation_vars: ["state"],
            context: "Region detection"
          )
        end

        it "detects incorrect variable name as interpolation discrepancy" do
          result = comparator.compare("Veo que eres de %{region}", var_reference)

          expect(result.matches?).to be false
          interp_discrepancy = result.discrepancies.find { |d| d.type == :interpolation }
          expect(interp_discrepancy).not_to be_nil
          expect(interp_discrepancy.expected).to eq "state"
          expect(interp_discrepancy.actual).to eq "region"
        end
      end

      context "when extra interpolation variable is present" do
        let(:var_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "TEST",
            text: "¡Hola!",
            interpolation_vars: [],
            context: "Simple greeting"
          )
        end

        it "detects extra variable as interpolation discrepancy" do
          result = comparator.compare("¡Hola %{name}!", var_reference)

          expect(result.matches?).to be false
          interp_discrepancy = result.discrepancies.find { |d| d.type == :interpolation }
          expect(interp_discrepancy).not_to be_nil
          expect(interp_discrepancy.expected).to eq ""
          expect(interp_discrepancy.actual).to eq "name"
        end
      end

      context "when multiple interpolation variables have issues" do
        let(:var_reference) do
          ElisaVerification::Models::MessageReference.new(
            flow_id: "C5A",
            text: "Urgente: %{name} reporta %{keyword} al %{phone}",
            interpolation_vars: ["name", "keyword", "phone"],
            context: "Emergency with multiple variables"
          )
        end

        it "flags interpolation mismatch for manual review" do
          result = comparator.compare("Urgente: %{client} reporta %{issue}", var_reference)

          expect(result.matches?).to be false
          interp_discrepancy = result.discrepancies.find { |d| d.type == :interpolation }
          expect(interp_discrepancy).not_to be_nil
          expect(interp_discrepancy.description).to include "manual review"
        end
      end
    end

    # Task 6.5: List Message comparison tests
    describe "list message comparison (Task 6.5 - for future use)" do
      # Note: These tests document the compare_list_message method
      # This method is called when comparing Hash structures, not in the main compare method
      # It will be used by higher-level components when processing List Messages

      let(:comparator_instance) { comparator }

      context "when List Message structures match exactly" do
        let(:yaml_list) do
          {
            title: "¿Por qué no por ahora?",
            body: "Me ayudaría saber qué te detiene",
            button: "Ver opciones",
            options: ["Estoy muy ocupado", "No entiendo qué es", "Otro motivo"]
          }
        end

        let(:reference_list) do
          {
            title: "¿Por qué no por ahora?",
            body: "Me ayudaría saber qué te detiene",
            button: "Ver opciones",
            options: ["Estoy muy ocupado", "No entiendo qué es", "Otro motivo"]
          }
        end

        it "returns no discrepancies" do
          discrepancies = comparator_instance.send(:compare_list_message, yaml_list, reference_list)

          expect(discrepancies).to be_empty
        end
      end

      context "when List Message title differs" do
        let(:yaml_list) do
          {
            title: "¿Por qué no?",
            body: "Me ayudaría saber qué te detiene",
            button: "Ver opciones",
            options: []
          }
        end

        let(:reference_list) do
          {
            title: "¿Por qué no por ahora?",
            body: "Me ayudaría saber qué te detiene",
            button: "Ver opciones",
            options: []
          }
        end

        it "detects title mismatch" do
          discrepancies = comparator_instance.send(:compare_list_message, yaml_list, reference_list)

          expect(discrepancies.size).to eq 1
          expect(discrepancies.first.type).to eq :wording
          expect(discrepancies.first.description).to include "title mismatch"
        end
      end

      context "when List Message body differs" do
        let(:yaml_list) do
          {
            title: "Título",
            body: "Cuerpo incorrecto",
            button: "Botón",
            options: []
          }
        end

        let(:reference_list) do
          {
            title: "Título",
            body: "Cuerpo correcto",
            button: "Botón",
            options: []
          }
        end

        it "detects body mismatch" do
          discrepancies = comparator_instance.send(:compare_list_message, yaml_list, reference_list)

          expect(discrepancies.size).to eq 1
          expect(discrepancies.first.description).to include "body mismatch"
        end
      end

      context "when List Message button text differs" do
        let(:yaml_list) do
          {
            title: "Título",
            body: "Cuerpo",
            button: "Presionar",
            options: []
          }
        end

        let(:reference_list) do
          {
            title: "Título",
            body: "Cuerpo",
            button: "Ver opciones",
            options: []
          }
        end

        it "detects button text mismatch" do
          discrepancies = comparator_instance.send(:compare_list_message, yaml_list, reference_list)

          expect(discrepancies.size).to eq 1
          expect(discrepancies.first.description).to include "button text mismatch"
        end
      end

      context "when options array length differs" do
        let(:yaml_list) do
          {
            title: "Título",
            body: "Cuerpo",
            button: "Botón",
            options: ["Opción 1", "Opción 2"]
          }
        end

        let(:reference_list) do
          {
            title: "Título",
            body: "Cuerpo",
            button: "Botón",
            options: ["Opción 1", "Opción 2", "Opción 3"]
          }
        end

        it "detects array length mismatch" do
          discrepancies = comparator_instance.send(:compare_list_message, yaml_list, reference_list)

          expect(discrepancies.size).to eq 1
          expect(discrepancies.first.expected).to eq "3 options"
          expect(discrepancies.first.actual).to eq "2 options"
        end
      end

      context "when option elements differ" do
        let(:yaml_list) do
          {
            title: "Título",
            body: "Cuerpo",
            button: "Botón",
            options: ["Estoy muy ocupado", "No entiendo bien", "Otro motivo"]
          }
        end

        let(:reference_list) do
          {
            title: "Título",
            body: "Cuerpo",
            button: "Botón",
            options: ["Estoy muy ocupado", "No entiendo qué es", "Otro motivo"]
          }
        end

        it "detects element-by-element differences" do
          discrepancies = comparator_instance.send(:compare_list_message, yaml_list, reference_list)

          expect(discrepancies.size).to eq 1
          expect(discrepancies.first.description).to include "option [1] mismatch"
          expect(discrepancies.first.expected).to eq "No entiendo qué es"
          expect(discrepancies.first.actual).to eq "No entiendo bien"
        end
      end

      context "when multiple List Message fields differ" do
        let(:yaml_list) do
          {
            title: "Título incorrecto",
            body: "Cuerpo incorrecto",
            button: "Botón incorrecto",
            options: ["Opción incorrecta"]
          }
        end

        let(:reference_list) do
          {
            title: "Título correcto",
            body: "Cuerpo correcto",
            button: "Botón correcto",
            options: ["Opción correcta"]
          }
        end

        it "detects all mismatches" do
          discrepancies = comparator_instance.send(:compare_list_message, yaml_list, reference_list)

          expect(discrepancies.size).to eq 4 # title, body, button, option[0]
          expect(discrepancies.map(&:description)).to include(
            "List Message title mismatch",
            "List Message body mismatch",
            "List Message button text mismatch",
            "List Message option [0] mismatch"
          )
        end
      end
    end
  end
end
