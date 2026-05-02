# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::ReviewCollectionService do
  let(:provider) { instance_double(Provider, id: 1, name: "Miguel García") }
  let(:client) { instance_double(Client, id: 42, name: "Mariana López", phone: "5212219876543") }

  let(:conversation) do
    instance_double(
      Conversation,
      id: 1,
      provider_id: 1,
      client_id: 42,
      context: {},
      "context=" => nil
    )
  end

  let(:job_double) do
    instance_double(
      Job,
      id: 8,
      provider: provider,
      client: client,
      status: "paid",
      review_sent: false
    )
  end

  let(:jobs_scope) { double("jobs_scope") }

  before do
    allow(conversation).to receive(:update!).and_return(true)
  end

  describe ".collecting_review?" do
    context "when conversation has review_collection context with awaiting_rating" do
      let(:conversation) do
        instance_double(
          Conversation,
          context: { "review_collection" => { "stage" => "awaiting_rating" } }
        )
      end

      it "returns true" do
        expect(described_class.collecting_review?(conversation)).to be(true)
      end
    end

    context "when conversation has review_collection context with awaiting_comment" do
      let(:conversation) do
        instance_double(
          Conversation,
          context: { "review_collection" => { "stage" => "awaiting_comment", "job_id" => 8, "rating" => 5 } }
        )
      end

      it "returns true" do
        expect(described_class.collecting_review?(conversation)).to be(true)
      end
    end

    context "when conversation has no review_collection context" do
      let(:conversation) do
        instance_double(Conversation, context: {})
      end

      it "returns false" do
        expect(described_class.collecting_review?(conversation)).to be(false)
      end
    end

    context "when conversation context is nil" do
      let(:conversation) do
        instance_double(Conversation, context: nil)
      end

      it "returns false" do
        expect(described_class.collecting_review?(conversation)).to be(false)
      end
    end
  end

  describe ".review_rating?" do
    context "when body is a number 1-5 and there is a pending review job" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:exists?).and_return(true)
      end

      (1..5).each do |rating|
        it "returns true for '#{rating}'" do
          expect(described_class.review_rating?(body: rating.to_s, conversation: conversation)).to be(true)
        end
      end
    end

    context "when body is not a valid rating" do
      %w[0 6 10 abc hola].each do |body|
        it "returns false for '#{body}'" do
          expect(described_class.review_rating?(body: body, conversation: conversation)).to be(false)
        end
      end
    end

    context "when body is nil or blank" do
      it "returns false for nil" do
        expect(described_class.review_rating?(body: nil, conversation: conversation)).to be(false)
      end

      it "returns false for empty string" do
        expect(described_class.review_rating?(body: "", conversation: conversation)).to be(false)
      end
    end

    context "when there is no pending review job" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:exists?).and_return(false)
      end

      it "returns false even for valid rating" do
        expect(described_class.review_rating?(body: "5", conversation: conversation)).to be(false)
      end
    end
  end

  describe "#process" do
    context "when client sends a valid rating (1-5)" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:order).and_return(jobs_scope)
        allow(jobs_scope).to receive(:first).and_return(job_double)
      end

      it "asks for an optional comment" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(result["message"]).to match(/más te gustó/)
      end

      it "stores rating in conversation context" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "4"
        )

        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including(
              "stage" => "awaiting_comment",
              "job_id" => 8,
              "rating" => 4
            )
          )
        )
      end

      it "does not save the message" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(result["should_save_message"]).to be(false)
      end
    end

    context "when client sends a comment after rating" do
      let(:conversation) do
        instance_double(
          Conversation,
          id: 1,
          provider_id: 1,
          client_id: 42,
          context: {
            "review_collection" => {
              "stage" => "awaiting_comment",
              "job_id" => 8,
              "rating" => 5
            }
          }
        )
      end

      before do
        allow(conversation).to receive(:update!).and_return(true)
        allow(Job).to receive(:find_by).with(id: 8).and_return(job_double)
        allow(Review).to receive(:create!).and_return(true)
        allow(job_double).to receive(:update!).and_return(true)
      end

      it "creates a Review with verified: true" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "Excelente trabajo, muy puntual"
        )

        expect(Review).to have_received(:create!).with(
          hash_including(
            provider: provider,
            client: client,
            job: job_double,
            rating: 5,
            comment: "Excelente trabajo, muy puntual",
            verified: true
          )
        )
      end

      it "marks the job as reviewed" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "Excelente trabajo"
        )

        expect(job_double).to have_received(:update!).with(review_sent: true)
      end

      it "clears the review collection context" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "Excelente trabajo"
        )

        expect(conversation).to have_received(:update!).with(
          context: hash_not_including("review_collection")
        )
      end

      it "saves the message (intent: review_collected)" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "Excelente trabajo"
        )

        expect(result["should_save_message"]).to be(true)
        expect(result["intent"]).to eq("review_collected")
      end
    end

    context "when client skips comment with 'no'" do
      let(:conversation) do
        instance_double(
          Conversation,
          id: 1,
          provider_id: 1,
          client_id: 42,
          context: {
            "review_collection" => {
              "stage" => "awaiting_comment",
              "job_id" => 8,
              "rating" => 4
            }
          }
        )
      end

      before do
        allow(conversation).to receive(:update!).and_return(true)
        allow(Job).to receive(:find_by).with(id: 8).and_return(job_double)
        allow(Review).to receive(:create!).and_return(true)
        allow(job_double).to receive(:update!).and_return(true)
      end

      it "creates a Review with nil comment" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "no"
        )

        expect(Review).to have_received(:create!).with(
          hash_including(
            rating: 4,
            comment: nil,
            verified: true
          )
        )
      end
    end

    context "when no reviewable job exists" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:order).and_return(jobs_scope)
        allow(jobs_scope).to receive(:first).and_return(nil)
      end

      it "returns a friendly message" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(result["message"]).to match(/No encontré/)
      end
    end
  end
end
