# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::Models::ComparisonResult do
  describe "#initialize" do
    it "creates a result with matches flag and discrepancies" do
      result = described_class.new(matches: true, discrepancies: [])

      expect(result.matches?).to be true
      expect(result.discrepancies).to eq([])
    end

    it "freezes the discrepancies array" do
      discrepancies = []
      result = described_class.new(matches: false, discrepancies: discrepancies)

      expect(result.discrepancies).to be_frozen
    end
  end

  describe "#matches?" do
    it "returns true when messages match" do
      result = described_class.new(matches: true, discrepancies: [])

      expect(result.matches?).to be true
    end

    it "returns false when messages don't match" do
      result = described_class.new(matches: false, discrepancies: [])

      expect(result.matches?).to be false
    end
  end

  describe "#discrepancies" do
    it "returns empty array when no discrepancies" do
      result = described_class.new(matches: true, discrepancies: [])

      expect(result.discrepancies).to eq([])
    end

    it "returns all discrepancies when present" do
      discrepancy1 = described_class::Discrepancy.new(
        type: :emoji,
        expected: "😊",
        actual: "",
        description: "Missing emoji"
      )
      discrepancy2 = described_class::Discrepancy.new(
        type: :wording,
        expected: "muy bien",
        actual: "bien",
        description: "Missing intensifier"
      )

      result = described_class.new(matches: false, discrepancies: [discrepancy1, discrepancy2])

      expect(result.discrepancies).to eq([discrepancy1, discrepancy2])
    end
  end

  describe "Discrepancy" do
    describe "#initialize" do
      it "creates a discrepancy with all attributes" do
        discrepancy = described_class::Discrepancy.new(
          type: :emoji,
          expected: "👋",
          actual: "",
          description: "Missing wave emoji"
        )

        expect(discrepancy.type).to eq(:emoji)
        expect(discrepancy.expected).to eq("👋")
        expect(discrepancy.actual).to eq("")
        expect(discrepancy.description).to eq("Missing wave emoji")
      end

      context "with valid types" do
        it "accepts :emoji type" do
          expect do
            described_class::Discrepancy.new(
              type: :emoji,
              expected: "😊",
              actual: "",
              description: "Missing emoji"
            )
          end.not_to raise_error
        end

        it "accepts :punctuation type" do
          expect do
            described_class::Discrepancy.new(
              type: :punctuation,
              expected: "¡",
              actual: "",
              description: "Missing opening exclamation"
            )
          end.not_to raise_error
        end

        it "accepts :wording type" do
          expect do
            described_class::Discrepancy.new(
              type: :wording,
              expected: "muy bien",
              actual: "bien",
              description: "Missing intensifier"
            )
          end.not_to raise_error
        end

        it "accepts :interpolation type" do
          expect do
            described_class::Discrepancy.new(
              type: :interpolation,
              expected: "%{name}",
              actual: "%{nombre}",
              description: "Wrong variable name"
            )
          end.not_to raise_error
        end
      end

      context "with invalid type" do
        it "raises ArgumentError for invalid type" do
          expect do
            described_class::Discrepancy.new(
              type: :invalid_type,
              expected: "test",
              actual: "test",
              description: "test"
            )
          end.to raise_error(ArgumentError, /Invalid discrepancy type: invalid_type/)
        end
      end
    end

    describe "#to_s" do
      it "returns a readable string representation" do
        discrepancy = described_class::Discrepancy.new(
          type: :emoji,
          expected: "😊",
          actual: "",
          description: "Missing smile emoji"
        )

        expect(discrepancy.to_s).to eq("[emoji] Missing smile emoji: expected '😊', got ''")
      end

      it "shows both expected and actual values" do
        discrepancy = described_class::Discrepancy.new(
          type: :wording,
          expected: "¡Que te vaya muy bien!",
          actual: "¡Que te vaya bien!",
          description: "Missing 'muy' intensifier"
        )

        expect(discrepancy.to_s).to include("expected '¡Que te vaya muy bien!'")
        expect(discrepancy.to_s).to include("got '¡Que te vaya bien!'")
      end
    end
  end
end
