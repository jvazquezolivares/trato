# frozen_string_literal: true

require "rails_helper"

RSpec.describe ElisaVerification::Models::ValidationResult do
  describe "#initialize" do
    it "creates a valid result with no errors" do
      result = described_class.new(valid: true, errors: [])

      expect(result.valid?).to be true
      expect(result.errors).to eq([])
    end

    it "creates an invalid result with errors" do
      errors = ["Line 42: mapping values are not allowed here"]
      result = described_class.new(valid: false, errors: errors)

      expect(result.valid?).to be false
      expect(result.errors).to eq(errors)
    end

    it "freezes the errors array" do
      errors = ["Some error"]
      result = described_class.new(valid: false, errors: errors)

      expect(result.errors).to be_frozen
    end
  end

  describe "#valid?" do
    context "when validation passed" do
      it "returns true" do
        result = described_class.new(valid: true, errors: [])

        expect(result.valid?).to be true
      end

      it "returns true even with empty error array" do
        result = described_class.new(valid: true, errors: [])

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
      end
    end

    context "when validation failed" do
      it "returns false" do
        result = described_class.new(valid: false, errors: ["Error message"])

        expect(result.valid?).to be false
      end

      it "returns false with multiple errors" do
        errors = [
          "YAML syntax error on line 10",
          "Invalid interpolation variable"
        ]
        result = described_class.new(valid: false, errors: errors)

        expect(result.valid?).to be false
        expect(result.errors.size).to eq(2)
      end
    end
  end

  describe "#errors" do
    context "when valid" do
      it "returns empty array" do
        result = described_class.new(valid: true, errors: [])

        expect(result.errors).to eq([])
        expect(result.errors).to be_empty
      end
    end

    context "when invalid" do
      it "returns single error" do
        result = described_class.new(
          valid: false,
          errors: ["Line 42: mapping values are not allowed here"]
        )

        expect(result.errors.size).to eq(1)
        expect(result.errors.first).to eq("Line 42: mapping values are not allowed here")
      end

      it "returns multiple errors" do
        errors = [
          "YAML syntax error: unexpected character",
          "Missing translation key: elisa.provider.welcome",
          "Invalid interpolation variable: %{unknow_var}"
        ]
        result = described_class.new(valid: false, errors: errors)

        expect(result.errors).to eq(errors)
        expect(result.errors.size).to eq(3)
      end

      it "preserves error order" do
        errors = ["First error", "Second error", "Third error"]
        result = described_class.new(valid: false, errors: errors)

        expect(result.errors[0]).to eq("First error")
        expect(result.errors[1]).to eq("Second error")
        expect(result.errors[2]).to eq("Third error")
      end
    end
  end

  describe "#to_s" do
    context "when valid" do
      it "returns VALID status" do
        result = described_class.new(valid: true, errors: [])

        expect(result.to_s).to eq("ValidationResult: VALID")
      end
    end

    context "when invalid" do
      it "returns INVALID status with error count" do
        result = described_class.new(
          valid: false,
          errors: ["Error 1"]
        )

        expect(result.to_s).to include("ValidationResult: INVALID")
        expect(result.to_s).to include("1 error(s)")
      end

      it "includes all error messages" do
        errors = [
          "YAML syntax error on line 10",
          "Invalid interpolation variable"
        ]
        result = described_class.new(valid: false, errors: errors)

        expect(result.to_s).to include("YAML syntax error on line 10")
        expect(result.to_s).to include("Invalid interpolation variable")
      end

      it "formats errors with bullet points" do
        errors = ["Error 1", "Error 2"]
        result = described_class.new(valid: false, errors: errors)

        expect(result.to_s).to include("  - Error 1")
        expect(result.to_s).to include("  - Error 2")
      end

      it "shows correct error count for multiple errors" do
        errors = ["Error 1", "Error 2", "Error 3"]
        result = described_class.new(valid: false, errors: errors)

        expect(result.to_s).to include("3 error(s)")
      end
    end
  end
end
