# frozen_string_literal: true

require "rails_helper"

RSpec.describe MessagePersistenceFilter do
  describe ".should_save?" do
    context "when intent is critical" do
      it "returns true regardless of body" do
        result = described_class.should_save?(body: "ok", intent: "job_registered")

        expect(result).to be(true)
      end
    end

    context "when body is trivial and intent is nil" do
      it "returns false" do
        result = described_class.should_save?(body: "gracias", intent: nil)

        expect(result).to be(false)
      end
    end

    context "when body is non-trivial and intent is non-critical" do
      it "returns nil (defers to Claude)" do
        result = described_class.should_save?(body: "Necesito un electricista", intent: "general_inquiry")

        expect(result).to be_nil
      end
    end
  end

  describe ".trivial_body?" do
    context "when body is a known trivial word" do
      %w[ok gracias perfecto listo entendido si no].each do |word|
        it "returns true for '#{word}'" do
          expect(described_class.trivial_body?(word)).to be(true)
        end

        it "returns true for '#{word.upcase}' (case insensitive)" do
          expect(described_class.trivial_body?(word.upcase)).to be(true)
        end
      end
    end

    context "when body is a standalone emoji" do
      %w[👍 😊 🙏 ✅ 👌].each do |emoji|
        it "returns true for '#{emoji}'" do
          expect(described_class.trivial_body?(emoji)).to be(true)
        end
      end

      it "returns true for multiple emojis" do
        expect(described_class.trivial_body?("👍😊")).to be(true)
      end
    end

    context "when body is blank or nil" do
      it "returns true for nil" do
        expect(described_class.trivial_body?(nil)).to be(true)
      end

      it "returns true for empty string" do
        expect(described_class.trivial_body?("")).to be(true)
      end

      it "returns true for whitespace only" do
        expect(described_class.trivial_body?("   ")).to be(true)
      end
    end

    context "when body has leading/trailing whitespace" do
      it "returns true for padded trivial word" do
        expect(described_class.trivial_body?("  ok  ")).to be(true)
      end
    end

    context "when body is non-trivial" do
      it "returns false for a sentence" do
        expect(described_class.trivial_body?("Necesito un electricista")).to be(false)
      end

      it "returns false for a number" do
        expect(described_class.trivial_body?("5")).to be(false)
      end

      it "returns false for mixed text and emoji" do
        expect(described_class.trivial_body?("Gracias por todo 👍")).to be(false)
      end
    end
  end

  describe ".critical_intent?" do
    context "when intent is in the critical set" do
      %w[
        job_registered payment_recorded appointment_confirmed
        appointment_cancelled complaint_received client_first_contact
        provider_unavailable expense_registered
      ].each do |intent|
        it "returns true for '#{intent}'" do
          expect(described_class.critical_intent?(intent)).to be(true)
        end
      end
    end

    context "when intent is not critical" do
      it "returns false for nil" do
        expect(described_class.critical_intent?(nil)).to be(false)
      end

      it "returns false for blank" do
        expect(described_class.critical_intent?("")).to be(false)
      end

      it "returns false for unknown intent" do
        expect(described_class.critical_intent?("general_inquiry")).to be(false)
      end
    end

    context "when intent has varied casing" do
      it "returns true for uppercase" do
        expect(described_class.critical_intent?("JOB_REGISTERED")).to be(true)
      end

      it "returns true with leading/trailing whitespace" do
        expect(described_class.critical_intent?("  job_registered  ")).to be(true)
      end
    end
  end
end
