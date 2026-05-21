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

    context "when client selects rating from List Message" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:order).and_return(jobs_scope)
        allow(jobs_scope).to receive(:first).and_return(job_double)
      end

      it "handles List Message selection ID '5' (⭐⭐⭐⭐⭐ Excelente)" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(result["message"]).to match(/más te gustó/)
        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including("rating" => 5)
          )
        )
      end

      it "handles List Message selection ID '4' (⭐⭐⭐⭐ Muy bueno)" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "4"
        )

        expect(result["message"]).to match(/más te gustó/)
        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including("rating" => 4)
          )
        )
      end

      it "handles List Message selection ID '3' (⭐⭐⭐ Bueno)" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "3"
        )

        expect(result["message"]).to match(/más te gustó/)
        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including("rating" => 3)
          )
        )
      end

      it "handles List Message selection ID '2' (⭐⭐ Regular)" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "2"
        )

        expect(result["message"]).to match(/más te gustó/)
        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including("rating" => 2)
          )
        )
      end

      it "handles List Message selection ID '1' (⭐ Malo)" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "1"
        )

        expect(result["message"]).to match(/más te gustó/)
        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including("rating" => 1)
          )
        )
      end

      it "extracts numeric value from List Message selection ID" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including(
              "stage" => "awaiting_comment",
              "job_id" => 8,
              "rating" => 5
            )
          )
        )
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

    context "when client sends invalid rating" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:order).and_return(jobs_scope)
        allow(jobs_scope).to receive(:first).and_return(job_double)
      end

      it "rejects rating 0" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "0"
        )

        expect(result["message"]).to match(/número del 1 al 5/)
        expect(result["should_save_message"]).to be(false)
      end

      it "rejects rating 6" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "6"
        )

        expect(result["message"]).to match(/número del 1 al 5/)
        expect(result["should_save_message"]).to be(false)
      end

      it "rejects negative ratings" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "-1"
        )

        expect(result["message"]).to match(/número del 1 al 5/)
        expect(result["should_save_message"]).to be(false)
      end

      it "rejects non-numeric input" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "excelente"
        )

        expect(result["message"]).to match(/número del 1 al 5/)
        expect(result["should_save_message"]).to be(false)
      end

      it "rejects empty string" do
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: ""
        )

        expect(result["message"]).to match(/número del 1 al 5/)
        expect(result["should_save_message"]).to be(false)
      end
    end

    context "rating selection requirement compliance (Requirement 14)" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:order).and_return(jobs_scope)
        allow(jobs_scope).to receive(:first).and_return(job_double)
      end

      it "accepts all 5 rating options from List Message" do
        (1..5).each do |rating|
          # Create fresh conversation for each rating to avoid state pollution
          fresh_conversation = instance_double(
            Conversation,
            id: 1,
            provider_id: 1,
            client_id: 42,
            context: {},
            "context=" => nil
          )
          allow(fresh_conversation).to receive(:update!).and_return(true)

          result = described_class.call(
            provider: provider, client: client,
            conversation: fresh_conversation, body: rating.to_s
          )

          expect(result["message"]).to match(/Gracias por tu calificación/)
          expect(fresh_conversation).to have_received(:update!).with(
            context: hash_including(
              "review_collection" => hash_including("rating" => rating)
            )
          )
        end
      end

      it "stores numeric value (1-5) in conversation context" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including(
              "rating" => 5 # AC3: Numeric value (1-5) stored
            )
          )
        )
      end

      it "maps List Message selection ID to numeric value" do
        # List Message IDs are already numeric strings ("1", "2", "3", "4", "5")
        # Service extracts numeric value directly
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "3"
        )

        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including(
              "rating" => 3 # Numeric value extracted from ID
            )
          )
        )
      end
    end

    context "rating selection with List Message format" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:order).and_return(jobs_scope)
        allow(jobs_scope).to receive(:first).and_return(job_double)
      end

      it "handles rating selection from WhatsApp List Message" do
        # When user selects "⭐⭐⭐⭐⭐ Excelente" from List Message,
        # WhatsApp sends the row ID ("5") as the message body
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(result["message"]).to match(/Gracias por tu calificación de 5/)
        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including(
              "stage" => "awaiting_comment",
              "rating" => 5
            )
          )
        )
      end

      it "processes rating immediately without AI interpretation" do
        # Rating selection is deterministic - no AI needed
        result = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "4"
        )

        # Should get immediate response asking for comment
        expect(result["message"]).to match(/Gracias por tu calificación/)
        expect(result["should_save_message"]).to be(false)
      end

      it "transitions to awaiting_comment stage after rating selection" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including(
              "stage" => "awaiting_comment"
            )
          )
        )
      end
    end

    context "rating persistence to Review model" do
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

      it "stores numeric rating value (1-5) in Review.rating field" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "Excelente trabajo"
        )

        expect(Review).to have_received(:create!).with(
          hash_including(
            rating: 5 # AC3: Numeric value (1-5) stored in Review rating field
          )
        )
      end

      it "creates verified review with rating from List Message selection" do
        described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "Muy buen servicio"
        )

        expect(Review).to have_received(:create!).with(
          hash_including(
            provider: provider,
            client: client,
            job: job_double,
            rating: 5,
            verified: true
          )
        )
      end
    end

    context "C7A star rating flow integration" do
      before do
        allow(Job).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:where).and_return(jobs_scope)
        allow(jobs_scope).to receive(:order).and_return(jobs_scope)
        allow(jobs_scope).to receive(:first).and_return(job_double)
      end

      it "completes C7A flow: List Message selection → comment → review created" do
        # Step 1: Client selects rating from List Message
        result1 = described_class.call(
          provider: provider, client: client,
          conversation: conversation, body: "5"
        )

        expect(result1["message"]).to match(/Gracias por tu calificación/)
        expect(conversation).to have_received(:update!).with(
          context: hash_including(
            "review_collection" => hash_including(
              "stage" => "awaiting_comment",
              "rating" => 5
            )
          )
        )

        # Step 2: Client provides comment
        conversation_with_rating = instance_double(
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
        allow(conversation_with_rating).to receive(:update!).and_return(true)
        allow(Job).to receive(:find_by).with(id: 8).and_return(job_double)
        allow(Review).to receive(:create!).and_return(true)
        allow(job_double).to receive(:update!).and_return(true)

        result2 = described_class.call(
          provider: provider, client: client,
          conversation: conversation_with_rating, body: "Excelente trabajo"
        )

        expect(result2["message"]).to match(/Tu reseña quedó registrada/)
        expect(Review).to have_received(:create!).with(
          hash_including(rating: 5, comment: "Excelente trabajo")
        )
      end

      it "supports all 5 star rating options in C7A flow" do
        # Verify all 5 rating options work end-to-end
        [1, 2, 3, 4, 5].each do |rating|
          # Create fresh conversation for each rating to avoid state pollution
          fresh_conversation = instance_double(
            Conversation,
            id: 1,
            provider_id: 1,
            client_id: 42,
            context: {},
            "context=" => nil
          )
          allow(fresh_conversation).to receive(:update!).and_return(true)

          result = described_class.call(
            provider: provider, client: client,
            conversation: fresh_conversation, body: rating.to_s
          )

          expect(result["message"]).to match(/Gracias por tu calificación de #{rating}/)
        end
      end
    end
  end
end
