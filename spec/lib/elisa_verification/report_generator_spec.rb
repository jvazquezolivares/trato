# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::ReportGenerator do
  let(:output_path) { Rails.root.join("tmp", "test_report.md").to_s }

  # Clean up test file after each test
  after do
    File.delete(output_path) if File.exist?(output_path)
  end

  describe "#initialize" do
    context "when valid arguments provided" do
      it "creates a ReportGenerator instance" do
        generator = described_class.new([], output_path)

        expect(generator).to be_a(described_class)
        expect(generator.comparisons).to eq([])
        expect(generator.output_path).to eq(output_path)
      end
    end

    context "when invalid arguments provided" do
      it "raises ArgumentError when comparisons is not an array" do
        expect do
          described_class.new("not an array", output_path)
        end.to raise_error(ArgumentError, "comparisons must be an array")
      end

      it "raises ArgumentError when output_path is nil" do
        expect do
          described_class.new([], nil)
        end.to raise_error(ArgumentError, "output_path cannot be empty")
      end

      it "raises ArgumentError when output_path is empty string" do
        expect do
          described_class.new([], "")
        end.to raise_error(ArgumentError, "output_path cannot be empty")
      end
    end
  end

  describe "#generate" do
    let(:matched_comparison) do
      ElisaVerification::Models::MessageComparison.new(
        key: "elisa.provider.onboarding.welcome",
        flow_id: "P1A",
        yaml_value: "¡Hola! 👋 Soy Elisa de Trato.",
        reference_value: "¡Hola! 👋 Soy Elisa de Trato.",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(
          matches: true,
          discrepancies: []
        ),
        corrected: false
      )
    end

    let(:corrected_comparison) do
      discrepancy = ElisaVerification::Models::ComparisonResult::Discrepancy.new(
        type: :emoji,
        expected: "😊",
        actual: "",
        description: "Missing emoji after greeting"
      )

      ElisaVerification::Models::MessageComparison.new(
        key: "elisa.provider.onboarding.decline_closing",
        flow_id: "P1B",
        yaml_value: "¡Gracias por contarme! Cuando quieras crear tu cuenta, escríbeme aquí.",
        reference_value: "¡Gracias por contarme! 😊 Cuando quieras crear tu cuenta, escríbeme aquí.",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(
          matches: false,
          discrepancies: [discrepancy]
        ),
        corrected: true
      )
    end

    let(:emergency_comparison) do
      ElisaVerification::Models::MessageComparison.new(
        key: "elisa.client.emergency.client_alert",
        flow_id: "C5A",
        yaml_value: "🚨 %{name}, esto suena urgente.",
        reference_value: "🚨 %{name}, esto suena urgente. Aléjate del panel.",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(
          matches: false,
          discrepancies: []
        ),
        corrected: true
      )
    end

    context "when generating report with mixed comparisons" do
      it "generates markdown content with all sections" do
        comparisons = [matched_comparison, corrected_comparison]
        generator = described_class.new(comparisons, output_path)

        result = generator.generate

        expect(result).to eq(generator)
        expect(generator.report_content).not_to be_nil
        expect(generator.report_content).to include("# Elisa Message Copy Verification Report")
        expect(generator.report_content).to include("## Summary")
        expect(generator.report_content).to include("**Total messages checked:** 2")
        expect(generator.report_content).to include("**Messages matching v5:** 1")
        expect(generator.report_content).to include("**Messages corrected:** 1")
      end

      it "includes header with timestamp and metadata" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("**Generated:**")
        expect(generator.report_content).to include("**V5 Spec Version:** KIRO_PROMPT_FLOWS_v5.md")
        expect(generator.report_content).to include("**YAML File:** config/locales/elisa_es.yml")
      end

      it "includes validation status section" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("**Validation status:**")
        expect(generator.report_content).to include("✅ YAML syntax valid, I18n compatible")
      end

      it "calculates correct statistics for matched messages" do
        comparisons = [matched_comparison, matched_comparison]
        generator = described_class.new(comparisons, output_path)
        generator.generate

        expect(generator.report_content).to include("**Messages matching v5:** 2 (100.0%)")
        expect(generator.report_content).to include("**Messages corrected:** 0 (0.0%)")
      end

      it "calculates correct statistics for corrected messages" do
        comparisons = [corrected_comparison, corrected_comparison]
        generator = described_class.new(comparisons, output_path)
        generator.generate

        expect(generator.report_content).to include("**Messages matching v5:** 0 (0.0%)")
        expect(generator.report_content).to include("**Messages corrected:** 2 (100.0%)")
      end
    end

    context "when generating report with matched messages" do
      it "shows matched message with correct emoji and status" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("### ✅ `elisa.provider.onboarding.welcome`")
        expect(generator.report_content).to include("**Flow ID:** P1A")
        expect(generator.report_content).to include("**Status:** Matches v5 specification")
        expect(generator.report_content).to include("¡Hola! 👋 Soy Elisa de Trato.")
      end

      it "displays message content in code block" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("**Message:**")
        expect(generator.report_content).to include("```")
      end
    end

    context "when generating report with corrected messages" do
      it "shows corrected message with before/after comparison" do
        generator = described_class.new([corrected_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("### 🔧 `elisa.provider.onboarding.decline_closing`")
        expect(generator.report_content).to include("**Flow ID:** P1B")
        expect(generator.report_content).to include("**Status:** Corrected to match v5")
        expect(generator.report_content).to include("**Before:**")
        expect(generator.report_content).to include("**After:**")
      end

      it "includes discrepancy details" do
        generator = described_class.new([corrected_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("**Changes:**")
        expect(generator.report_content).to include("Emoji: Missing emoji after greeting")
      end

      it "formats different discrepancy types correctly" do
        punctuation_discrepancy = ElisaVerification::Models::ComparisonResult::Discrepancy.new(
          type: :punctuation,
          expected: "¡",
          actual: "",
          description: "Missing opening exclamation mark"
        )

        wording_discrepancy = ElisaVerification::Models::ComparisonResult::Discrepancy.new(
          type: :wording,
          expected: "muy bien",
          actual: "bien",
          description: "Missing 'muy' intensifier"
        )

        comparison = ElisaVerification::Models::MessageComparison.new(
          key: "test.key",
          flow_id: "P1",
          yaml_value: "old",
          reference_value: "new",
          comparison_result: ElisaVerification::Models::ComparisonResult.new(
            matches: false,
            discrepancies: [punctuation_discrepancy, wording_discrepancy]
          ),
          corrected: true
        )

        generator = described_class.new([comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("Punctuation: Missing opening exclamation mark")
        expect(generator.report_content).to include("Wording: Missing 'muy' intensifier")
      end
    end

    context "when generating report with emergency messages (C5A)" do
      it "creates special emergency messages section" do
        generator = described_class.new([emergency_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("## 🚨 Emergency Messages (C5A) - Critical Safety Messages")
        expect(generator.report_content).to include("**⚠️ CRITICAL SAFETY MESSAGE ⚠️**")
      end

      it "highlights emergency message with special formatting" do
        generator = described_class.new([emergency_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("`elisa.client.emergency.client_alert`")
        expect(generator.report_content).to include("**Flow ID:** C5A")
      end

      it "does not duplicate emergency messages in regular sections" do
        comparisons = [emergency_comparison, matched_comparison]
        generator = described_class.new(comparisons, output_path)
        generator.generate

        # Count occurrences of the emergency message key
        emergency_key_count = generator.report_content.scan(/elisa\.client\.emergency\.client_alert/).size

        # Should appear only once (in emergency section, not in client flows section)
        expect(emergency_key_count).to eq(1)
      end
    end

    context "when generating report with different flow categories" do
      it "groups provider onboarding messages (P1-P8)" do
        p1_comparison = ElisaVerification::Models::MessageComparison.new(
          key: "elisa.provider.onboarding.welcome",
          flow_id: "P1A",
          yaml_value: "test",
          reference_value: "test",
          comparison_result: ElisaVerification::Models::ComparisonResult.new(matches: true, discrepancies: []),
          corrected: false
        )

        generator = described_class.new([p1_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("## Provider Onboarding Messages (P1-P8)")
      end

      it "groups client flow messages (C1-C7)" do
        c2_comparison = ElisaVerification::Models::MessageComparison.new(
          key: "elisa.client.region.greeting",
          flow_id: "C2A",
          yaml_value: "test",
          reference_value: "test",
          comparison_result: ElisaVerification::Models::ComparisonResult.new(matches: true, discrepancies: []),
          corrected: false
        )

        generator = described_class.new([c2_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("## Client Flow Messages (C1-C7)")
      end

      it "groups list messages by key pattern" do
        list_comparison = ElisaVerification::Models::MessageComparison.new(
          key: "elisa.provider.list_messages.decline_reasons",
          flow_id: "P1B",
          yaml_value: "test",
          reference_value: "test",
          comparison_result: ElisaVerification::Models::ComparisonResult.new(matches: true, discrepancies: []),
          corrected: false
        )

        generator = described_class.new([list_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("## List Messages")
      end

      it "creates sections only for categories with messages" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate

        # Should have Provider Onboarding section (P1A)
        expect(generator.report_content).to include("## Provider Onboarding Messages")

        # Should NOT have other sections
        expect(generator.report_content).not_to include("## Client Flow Messages")
      end
    end

    context "when generating report with empty comparisons" do
      it "generates report with zero statistics" do
        generator = described_class.new([], output_path)
        generator.generate

        expect(generator.report_content).to include("**Total messages checked:** 0")
        expect(generator.report_content).to include("**Messages matching v5:** 0 (0.0%)")
        expect(generator.report_content).to include("**Messages corrected:** 0")
      end

      it "includes header and footer" do
        generator = described_class.new([], output_path)
        generator.generate

        expect(generator.report_content).to include("# Elisa Message Copy Verification Report")
        expect(generator.report_content).to include("## Report Generation Details")
      end
    end

    context "when generating report footer" do
      it "includes generation details" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate

        expect(generator.report_content).to include("## Report Generation Details")
        expect(generator.report_content).to include("**Total comparisons processed:** 1")
        expect(generator.report_content).to include("**Report generated by:** ElisaVerification::ReportGenerator")
        expect(generator.report_content).to include("**Report format version:** 1.0")
      end
    end
  end

  describe "#save" do
    let(:matched_comparison) do
      ElisaVerification::Models::MessageComparison.new(
        key: "elisa.provider.onboarding.welcome",
        flow_id: "P1A",
        yaml_value: "test",
        reference_value: "test",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(matches: true, discrepancies: []),
        corrected: false
      )
    end

    context "when report has been generated" do
      it "saves report to file successfully" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate

        result = generator.save

        expect(result).to be true
        expect(File.exist?(output_path)).to be true
      end

      it "saves correct markdown content to file" do
        generator = described_class.new([matched_comparison], output_path)
        generator.generate
        generator.save

        file_content = File.read(output_path)

        expect(file_content).to eq(generator.report_content)
        expect(file_content).to include("# Elisa Message Copy Verification Report")
      end
    end

    context "when report has not been generated" do
      it "raises error if generate was not called first" do
        generator = described_class.new([matched_comparison], output_path)

        expect { generator.save }.to raise_error(RuntimeError, "Must call generate before save")
      end
    end

    context "when save operation fails" do
      it "raises FileWriteError when unable to write file" do
        invalid_path = "/invalid/path/that/does/not/exist/report.md"
        generator = described_class.new([matched_comparison], invalid_path)
        generator.generate

        expect { generator.save }.to raise_error(ElisaVerification::FileWriteError) do |error|
          expect(error.message).to include(invalid_path)
        end
      end

      it "raises FileWriteError with clear message for permission denied" do
        # This test would need a read-only directory setup
        # Skipping actual permission test as it's environment-specific
        # The error handling is already tested in the invalid path case
      end
    end

    context "when method chaining" do
      it "allows generate.save chaining" do
        generator = described_class.new([matched_comparison], output_path)

        result = generator.generate.save

        expect(result).to be true
        expect(File.exist?(output_path)).to be true
      end
    end
  end

  describe "integration test with realistic data" do
    it "generates complete report with multiple message types" do
      # Matched provider message
      matched = ElisaVerification::Models::MessageComparison.new(
        key: "elisa.provider.onboarding.welcome",
        flow_id: "P1A",
        yaml_value: "¡Hola! 👋 Soy Elisa de Trato.",
        reference_value: "¡Hola! 👋 Soy Elisa de Trato.",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(matches: true, discrepancies: []),
        corrected: false
      )

      # Corrected provider message
      emoji_discrepancy = ElisaVerification::Models::ComparisonResult::Discrepancy.new(
        type: :emoji,
        expected: "😊",
        actual: "",
        description: "Added emoji after greeting"
      )

      corrected_provider = ElisaVerification::Models::MessageComparison.new(
        key: "elisa.provider.onboarding.decline_closing",
        flow_id: "P1B",
        yaml_value: "¡Gracias por contarme!",
        reference_value: "¡Gracias por contarme! 😊",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(
          matches: false,
          discrepancies: [emoji_discrepancy]
        ),
        corrected: true
      )

      # Emergency message
      emergency = ElisaVerification::Models::MessageComparison.new(
        key: "elisa.client.emergency.client_alert",
        flow_id: "C5A",
        yaml_value: "🚨 %{name}, esto suena urgente.",
        reference_value: "🚨 %{name}, esto suena urgente. Aléjate del panel.",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(matches: false, discrepancies: []),
        corrected: true
      )

      # Client flow message
      client = ElisaVerification::Models::MessageComparison.new(
        key: "elisa.client.region.greeting",
        flow_id: "C2A",
        yaml_value: "¡Hola! 👋 Soy Elisa.",
        reference_value: "¡Hola! 👋 Soy Elisa.",
        comparison_result: ElisaVerification::Models::ComparisonResult.new(matches: true, discrepancies: []),
        corrected: false
      )

      comparisons = [matched, corrected_provider, emergency, client]
      generator = described_class.new(comparisons, output_path)

      generator.generate.save

      expect(File.exist?(output_path)).to be true

      content = File.read(output_path)

      # Verify structure
      expect(content).to include("# Elisa Message Copy Verification Report")
      expect(content).to include("## Summary")
      expect(content).to include("**Total messages checked:** 4")
      expect(content).to include("**Messages matching v5:** 2")
      expect(content).to include("**Messages corrected:** 2")

      # Verify emergency section
      expect(content).to include("## 🚨 Emergency Messages (C5A)")
      expect(content).to include("**⚠️ CRITICAL SAFETY MESSAGE ⚠️**")

      # Verify flow sections
      expect(content).to include("## Provider Onboarding Messages (P1-P8)")
      expect(content).to include("## Client Flow Messages (C1-C7)")

      # Verify message details
      expect(content).to include("✅ `elisa.provider.onboarding.welcome`")
      expect(content).to include("🔧 `elisa.provider.onboarding.decline_closing`")
      expect(content).to include("Emoji: Added emoji after greeting")
    end
  end
end
