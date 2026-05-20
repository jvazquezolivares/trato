# frozen_string_literal: true

require "rails_helper"

RSpec.describe OnboardingDecline, type: :model do
  describe "validations" do
    it "requires phone" do
      decline = described_class.new(reason: "busy")
      expect(decline).not_to be_valid
      expect(decline.errors[:phone]).to include("can't be blank")
    end

    it "requires reason" do
      decline = described_class.new(phone: "5212211234567")
      expect(decline).not_to be_valid
      expect(decline.errors[:reason]).to include("can't be blank")
    end

    it "is valid with phone and reason" do
      decline = described_class.new(
        phone: "5212211234567",
        reason: "busy",
        context: { stage: "onboarding" }
      )
      expect(decline).to be_valid
    end
  end

  describe "scopes" do
    let!(:decline1) do
      described_class.create!(
        phone: "5212211234567",
        reason: "busy",
        created_at: 2.days.ago
      )
    end

    let!(:decline2) do
      described_class.create!(
        phone: "5212211234567",
        reason: "dont_understand",
        created_at: 1.day.ago
      )
    end

    let!(:decline3) do
      described_class.create!(
        phone: "5219876543210",
        reason: "not_worth_it",
        created_at: Time.current
      )
    end

    describe ".by_phone" do
      it "returns declines for specific phone number" do
        results = described_class.by_phone("5212211234567")
        expect(results).to contain_exactly(decline1, decline2)
      end

      it "returns empty array for phone with no declines" do
        results = described_class.by_phone("5211111111111")
        expect(results).to be_empty
      end
    end

    describe ".recent" do
      it "returns declines ordered by created_at descending" do
        results = described_class.recent
        expect(results).to eq([decline3, decline2, decline1])
      end
    end
  end

  describe "context storage" do
    it "stores context as jsonb" do
      decline = described_class.create!(
        phone: "5212211234567",
        reason: "busy",
        context: {
          stage: "onboarding",
          declined_at: Time.current.iso8601,
          additional_info: "User was in a hurry"
        }
      )

      expect(decline.context).to be_a(Hash)
      expect(decline.context["stage"]).to eq("onboarding")
      expect(decline.context["additional_info"]).to eq("User was in a hurry")
    end

    it "allows nil context" do
      decline = described_class.create!(
        phone: "5212211234567",
        reason: "busy",
        context: nil
      )

      expect(decline.context).to be_nil
    end
  end
end
