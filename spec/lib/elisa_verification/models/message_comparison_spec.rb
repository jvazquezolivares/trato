# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::Models::MessageComparison do
  # Mock ComparisonResult for testing purposes
  let(:matching_comparison_result) do
    instance_double("ComparisonResult", matches?: true)
  end

  let(:non_matching_comparison_result) do
    instance_double("ComparisonResult", matches?: false)
  end

  describe "#initialize" do
    it "initializes with all required attributes" do
      comparison = described_class.new(
        key: "elisa.provider.onboarding.welcome",
        flow_id: "P1A",
        yaml_value: "¡Hola! 👋 Soy Elisa de Trato",
        reference_value: "¡Hola! 👋 Soy Elisa de Trato",
        comparison_result: matching_comparison_result,
        corrected: false
      )

      expect(comparison.key).to eq("elisa.provider.onboarding.welcome")
      expect(comparison.flow_id).to eq("P1A")
      expect(comparison.yaml_value).to eq("¡Hola! 👋 Soy Elisa de Trato")
      expect(comparison.reference_value).to eq("¡Hola! 👋 Soy Elisa de Trato")
      expect(comparison.comparison_result).to eq(matching_comparison_result)
      expect(comparison.corrected).to be(false)
    end
  end

  describe "#matched?" do
    context "when comparison result indicates a match" do
      it "returns true" do
        comparison = described_class.new(
          key: "elisa.provider.onboarding.welcome",
          flow_id: "P1A",
          yaml_value: "¡Hola! 👋 Soy Elisa",
          reference_value: "¡Hola! 👋 Soy Elisa",
          comparison_result: matching_comparison_result,
          corrected: false
        )

        expect(comparison.matched?).to be(true)
      end
    end

    context "when comparison result indicates no match" do
      it "returns false" do
        comparison = described_class.new(
          key: "elisa.provider.onboarding.welcome",
          flow_id: "P1A",
          yaml_value: "¡Hola! Soy Elisa",
          reference_value: "¡Hola! 👋 Soy Elisa",
          comparison_result: non_matching_comparison_result,
          corrected: false
        )

        expect(comparison.matched?).to be(false)
      end
    end

    context "when comparison result is nil" do
      it "returns false as a safe default" do
        comparison = described_class.new(
          key: "elisa.provider.onboarding.welcome",
          flow_id: "P1A",
          yaml_value: "¡Hola! Soy Elisa",
          reference_value: "¡Hola! 👋 Soy Elisa",
          comparison_result: nil,
          corrected: false
        )

        expect(comparison.matched?).to be(false)
      end
    end
  end

  describe "#corrected?" do
    context "when message was corrected" do
      it "returns true" do
        comparison = described_class.new(
          key: "elisa.provider.onboarding.decline_closing",
          flow_id: "P1B",
          yaml_value: "¡Gracias por contarme!",
          reference_value: "¡Gracias por contarme! 😊 — Elisa",
          comparison_result: non_matching_comparison_result,
          corrected: true
        )

        expect(comparison.corrected?).to be(true)
      end
    end

    context "when message was not corrected" do
      it "returns false" do
        comparison = described_class.new(
          key: "elisa.provider.onboarding.welcome",
          flow_id: "P1A",
          yaml_value: "¡Hola! 👋 Soy Elisa",
          reference_value: "¡Hola! 👋 Soy Elisa",
          comparison_result: matching_comparison_result,
          corrected: false
        )

        expect(comparison.corrected?).to be(false)
      end
    end

    context "when corrected is nil" do
      it "returns false" do
        comparison = described_class.new(
          key: "elisa.provider.onboarding.welcome",
          flow_id: "P1A",
          yaml_value: "¡Hola! Soy Elisa",
          reference_value: "¡Hola! 👋 Soy Elisa",
          comparison_result: non_matching_comparison_result,
          corrected: nil
        )

        expect(comparison.corrected?).to be(false)
      end
    end
  end

  describe "emergency message tracking" do
    context "when tracking C5A client emergency alert" do
      it "stores critical emergency message metadata" do
        comparison = described_class.new(
          key: "elisa.client.emergency.client_alert",
          flow_id: "C5A",
          yaml_value: "🚨 %{name}, esto suena urgente...",
          reference_value: "🚨 %{name}, esto suena urgente. Aléjate del panel...",
          comparison_result: non_matching_comparison_result,
          corrected: true
        )

        expect(comparison.flow_id).to eq("C5A")
        expect(comparison.yaml_value).to include("🚨")
        expect(comparison.reference_value).to include("Aléjate del panel")
        expect(comparison.corrected?).to be(true)
      end
    end
  end

  describe "list message tracking" do
    context "when tracking P1B decline reasons list message" do
      it "stores list message structure as hash" do
        yaml_list = {
          "title" => "¿Por qué no por ahora?",
          "body" => "Me ayudaría saber qué te detiene",
          "options" => ["Estoy muy ocupado", "No entiendo qué es"]
        }

        reference_list = {
          "title" => "¿Por qué no por ahora?",
          "body" => "Me ayudaría saber qué te detiene",
          "options" => ["Estoy muy ocupado ahorita", "No entiendo bien qué es Trato"]
        }

        comparison = described_class.new(
          key: "elisa.provider.list_messages.decline_reasons",
          flow_id: "P1B",
          yaml_value: yaml_list,
          reference_value: reference_list,
          comparison_result: non_matching_comparison_result,
          corrected: true
        )

        expect(comparison.yaml_value).to be_a(Hash)
        expect(comparison.yaml_value["title"]).to eq("¿Por qué no por ahora?")
        expect(comparison.corrected?).to be(true)
      end
    end
  end
end
