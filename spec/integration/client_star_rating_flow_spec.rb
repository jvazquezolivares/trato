# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Client Star Rating Flow Integration (C7A)", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:client_phone) { "5219511234567" }
  let(:provider_phone) { "5212291234567" }
  let(:provider_short_uuid) { "abc12345" }

  before do
    # Mock WhatsApp service
    allow(WhatsAppService).to receive(:send_message).and_return(nil)
    allow(WhatsAppService).to receive(:send_list_message).and_return(nil)
    allow(WhatsAppService).to receive(:send_message_with_buttons).and_return(nil)

    # Clear any enqueued jobs before each test
    clear_enqueued_jobs
  end

  describe "complete C7A star rating flow end-to-end" do
    let!(:provider) do
      Provider.create!(
        name: "Miguel García",
        phone: provider_phone,
        short_uuid: provider_short_uuid,
        city: "Veracruz",
        active: true
      )
    end

    let!(:client) do
      Client.create!(
        name: "Mariana López",
        phone: client_phone
      )
    end

    let!(:conversation) do
      Conversation.create!(
        provider: provider,
        client: client,
        phone: client_phone,
        stage: "active",
        context: {}
      )
    end

    let!(:job) do
      Job.create!(
        provider: provider,
        client: client,
        status: "paid",
        review_sent: false,
        review_attempts: 0,
        service_date: 2.days.ago.to_date
      )
    end

    context "when ReviewRequestJob sends rating request" do
      it "sends List Message with 5 star rating options" do
        # Execute ReviewRequestJob
        ReviewRequestJob.new.perform(job.id)

        # Verify List Message was sent
        expect(WhatsAppService).to have_received(:send_list_message) do |args|
          expect(args[:to]).to eq(client_phone)
          payload = args[:payload]

          # Verify it's a list message for rating
          expect(payload[:type]).to eq("list")
          expect(payload[:header][:text]).to match(/calificarías|calificación/i)

          # Verify 5 star rating options are present
          rows = payload[:action][:sections][0][:rows]
          expect(rows.length).to eq(5)

          # Verify each option has correct structure
          rating_ids = rows.map { |row| row[:id] }
          expect(rating_ids).to match_array(%w[5 4 3 2 1])

          # Verify titles contain stars
          rows.each do |row|
            expect(row[:title]).to match(/⭐/)
          end
        end

        # Verify attempt was tracked
        job.reload
        expect(job.review_attempts).to eq(1)
        expect(job.review_requested_at).to be_present
      end
    end

    context "when client selects rating from List Message" do
      before do
        # Simulate that ReviewRequestJob already sent the request
        job.update!(review_attempts: 1, review_requested_at: Time.current)
      end

      it "stores rating and asks for comment" do
        # Client selects 5 stars from List Message
        response = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "5"
        )

        # Verify conversation context was updated with rating
        conversation.reload
        expect(conversation.context["review_collection"]).to be_present
        expect(conversation.context["review_collection"]["stage"]).to eq("awaiting_comment")
        expect(conversation.context["review_collection"]["rating"]).to eq(5)
        expect(conversation.context["review_collection"]["job_id"]).to eq(job.id)

        # Verify comment request message is in response
        expect(response["message"]).to match(/Gracias por tu calificación.*más te gustó/m)
        expect(response["message"]).to include(provider.name)
      end

      it "handles all 5 rating options correctly" do
        [
          { id: "5", value: 5 },
          { id: "4", value: 4 },
          { id: "3", value: 3 },
          { id: "2", value: 2 },
          { id: "1", value: 1 }
        ].each do |rating_option|
          # Reset conversation context for each test
          conversation.update!(context: {})

          # Client selects rating
          response = Assistants::ReviewCollectionService.call(
            provider: provider,
            client: client,
            conversation: conversation,
            body: rating_option[:id]
          )

          # Verify rating was stored correctly
          conversation.reload
          expect(conversation.context["review_collection"]["rating"]).to eq(rating_option[:value])

          # Verify comment request mentions the rating
          expect(response["message"]).to match(/calificación de #{rating_option[:value]}/)
        end
      end
    end

    context "when client provides comment after rating" do
      before do
        # Set up conversation with rating already collected
        conversation.update!(
          context: {
            "review_collection" => {
              "stage" => "awaiting_comment",
              "job_id" => job.id,
              "rating" => 5
            }
          }
        )
      end

      it "creates verified Review and completes flow" do
        # Client sends comment
        response = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "Excelente trabajo, muy puntual y profesional"
        )

        # Verify Review was created
        expect(Review.count).to eq(1)
        review = Review.last
        expect(review.provider).to eq(provider)
        expect(review.client).to eq(client)
        expect(review.job).to eq(job)
        expect(review.rating).to eq(5)
        expect(review.comment).to eq("Excelente trabajo, muy puntual y profesional")
        expect(review.verified).to be(true)

        # Verify job was marked as reviewed
        job.reload
        expect(job.review_sent).to be(true)

        # Verify review collection context was cleared
        conversation.reload
        expect(conversation.context["review_collection"]).to be_nil

        # Verify confirmation message is in response
        expect(response["message"]).to match(/Tu reseña quedó registrada/)
        expect(response["intent"]).to eq("review_collected")
      end

      it "handles client skipping comment with 'no'" do
        # Client sends "no" to skip comment
        Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "no"
        )

        # Verify Review was created without comment
        expect(Review.count).to eq(1)
        review = Review.last
        expect(review.rating).to eq(5)
        expect(review.comment).to be_nil
        expect(review.verified).to be(true)

        # Verify job was marked as reviewed
        job.reload
        expect(job.review_sent).to be(true)

        # Verify context was cleared
        conversation.reload
        expect(conversation.context["review_collection"]).to be_nil
      end

      it "handles client skipping comment with empty message" do
        # Client sends empty message to skip comment
        Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: ""
        )

        # Verify Review was created without comment
        expect(Review.count).to eq(1)
        review = Review.last
        expect(review.rating).to eq(5)
        expect(review.comment).to be_nil
        expect(review.verified).to be(true)
      end
    end

    context "when testing complete flow from start to finish" do
      it "completes entire C7A flow: request → rating → comment → review" do
        # Step 1: ReviewRequestJob sends rating request
        ReviewRequestJob.new.perform(job.id)

        expect(WhatsAppService).to have_received(:send_list_message) do |args|
          expect(args[:to]).to eq(client_phone)
          expect(args[:payload][:type]).to eq("list")
        end

        job.reload
        expect(job.review_attempts).to eq(1)

        # Step 2: Client selects 5 stars from List Message
        response = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "5"
        )

        conversation.reload
        expect(conversation.context["review_collection"]["rating"]).to eq(5)
        expect(conversation.context["review_collection"]["stage"]).to eq("awaiting_comment")

        expect(response["message"]).to match(/Gracias por tu calificación/)

        # Step 3: Client provides comment
        response = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "Muy buen servicio, lo recomiendo"
        )

        # Verify Review was created
        expect(Review.count).to eq(1)
        review = Review.last
        expect(review.rating).to eq(5)
        expect(review.comment).to eq("Muy buen servicio, lo recomiendo")
        expect(review.verified).to be(true)

        # Verify job was marked as reviewed
        job.reload
        expect(job.review_sent).to be(true)

        # Verify context was cleared
        conversation.reload
        expect(conversation.context["review_collection"]).to be_nil

        # Verify confirmation message is in response
        expect(response["message"]).to match(/Tu reseña quedó registrada/)
      end

      it "completes flow with different rating values" do
        [1, 2, 3, 4, 5].each_with_index do |rating_value, index|
          # Reset state for each iteration
          Review.destroy_all

          # Reload and reset job state BEFORE clearing conversation
          job.reload
          job.update!(review_sent: false, review_attempts: 0)

          # Reload and clear conversation context
          conversation.reload
          conversation.update!(context: {})

          # Step 1: Send rating request
          ReviewRequestJob.new.perform(job.id)

          # Step 2: Client selects rating
          # Reload conversation before calling service to ensure fresh state
          conversation.reload
          Assistants::ReviewCollectionService.call(
            provider: provider,
            client: client,
            conversation: conversation,
            body: rating_value.to_s
          )

          # Reload conversation to get updated context
          conversation.reload

          # Verify context was updated
          expect(conversation.context["review_collection"]).to be_present, "Review collection context should exist for rating #{rating_value} (iteration #{index + 1})"
          expect(conversation.context["review_collection"]["stage"]).to eq("awaiting_comment")

          # Step 3: Client provides comment
          # Reload conversation again before calling service
          conversation.reload
          Assistants::ReviewCollectionService.call(
            provider: provider,
            client: client,
            conversation: conversation,
            body: "Comentario para rating #{rating_value}"
          )

          # Verify Review was created with correct rating
          review = Review.last
          expect(review).not_to be_nil, "Review should exist for rating #{rating_value} (iteration #{index + 1})"
          expect(review.rating).to eq(rating_value)
          expect(review.comment).to eq("Comentario para rating #{rating_value}")
        end
      end
    end

    context "when testing List Message payload structure" do
      it "sends List Message with correct structure and all 5 options" do
        ReviewRequestJob.new.perform(job.id)

        expect(WhatsAppService).to have_received(:send_list_message) do |args|
          payload = args[:payload]

          # Verify type
          expect(payload[:type]).to eq("list")

          # Verify header
          expect(payload[:header][:type]).to eq("text")
          expect(payload[:header][:text]).to match(/calificarías|calificación/i)

          # Verify body
          expect(payload[:body][:text]).to be_present

          # Verify action structure
          expect(payload[:action][:button]).to eq("Ver opciones")
          expect(payload[:action][:sections]).to be_an(Array)
          expect(payload[:action][:sections].length).to eq(1)

          # Verify all 5 rating options are present
          rows = payload[:action][:sections][0][:rows]
          expect(rows.length).to eq(5)

          # Verify each option has id and title
          expected_ids = %w[5 4 3 2 1]
          actual_ids = rows.map { |row| row[:id] }
          expect(actual_ids).to match_array(expected_ids)

          # Verify titles contain stars and are within WhatsApp limit
          rows.each do |row|
            expect(row[:id]).to be_present
            expect(row[:title]).to be_present
            expect(row[:title]).to match(/⭐/)
            expect(row[:title].length).to be <= 24 # WhatsApp limit
          end

          # Verify specific titles match requirements
          titles = rows.map { |row| row[:title] }
          expect(titles).to include("⭐⭐⭐⭐⭐ Excelente")
          expect(titles).to include("⭐⭐⭐⭐ Muy bueno")
          expect(titles).to include("⭐⭐⭐ Bueno")
          expect(titles).to include("⭐⭐ Regular")
          expect(titles).to include("⭐ Malo")
        end
      end
    end

    context "when testing error cases" do
      it "handles invalid rating gracefully" do
        # Client sends invalid rating (not 1-5)
        result = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "10"
        )

        # Verify error message was returned
        expect(result["message"]).to match(/número del 1 al 5/)

        # Verify no Review was created
        expect(Review.count).to eq(0)

        # Verify job was not marked as reviewed
        job.reload
        expect(job.review_sent).to be(false)
      end

      it "handles missing job gracefully" do
        # Delete the job
        job.destroy

        # Client sends rating
        result = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "5"
        )

        # Verify friendly error message was returned
        expect(result["message"]).to match(/No encontré.*trabajo pendiente/i)

        # Verify no Review was created
        expect(Review.count).to eq(0)
      end

      it "handles job already reviewed" do
        # Mark job as already reviewed
        job.update!(review_sent: true)

        # Try to send review request
        ReviewRequestJob.new.perform(job.id)

        # Verify no List Message was sent
        expect(WhatsAppService).not_to have_received(:send_list_message)
      end
    end

    context "when testing retry mechanism" do
      it "reschedules ReviewRequestJob if under max attempts" do
        freeze_time = Time.current

        travel_to(freeze_time) do
          # First attempt
          ReviewRequestJob.new.perform(job.id)

          job.reload
          expect(job.review_attempts).to eq(1)

          # Verify job was rescheduled
          expect(ReviewRequestJob).to have_been_enqueued.with(job.id)
        end
      end

      it "does not reschedule after max attempts" do
        # Set job to max attempts
        job.update!(review_attempts: 3)

        # Try to send review request
        ReviewRequestJob.new.perform(job.id)

        # Verify no List Message was sent
        expect(WhatsAppService).not_to have_received(:send_list_message)

        # Verify job was not rescheduled
        expect(ReviewRequestJob).not_to have_been_enqueued
      end
    end

    context "when testing conversation stage transitions" do
      it "transitions through correct stages: nil → awaiting_comment → cleared" do
        # Initial state: no review_collection context
        expect(conversation.context["review_collection"]).to be_nil

        # Stage 1: Client selects rating
        Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "5"
        )

        # Verify transition to awaiting_comment
        conversation.reload
        expect(conversation.context["review_collection"]["stage"]).to eq("awaiting_comment")
        expect(conversation.context["review_collection"]["rating"]).to eq(5)

        # Stage 2: Client provides comment
        Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "Excelente trabajo"
        )

        # Verify context was cleared
        conversation.reload
        expect(conversation.context["review_collection"]).to be_nil
      end
    end

    context "when testing message content and tone" do
      it "sends friendly confirmation message after review is collected" do
        # Set up conversation with rating already collected
        conversation.update!(
          context: {
            "review_collection" => {
              "stage" => "awaiting_comment",
              "job_id" => job.id,
              "rating" => 5
            }
          }
        )

        # Client sends comment
        response = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "Excelente trabajo"
        )

        # Verify exact message content
        expected_message = "¡Listo! Tu reseña quedó registrada. Muchas gracias por tomarte el tiempo 🙏"

        expect(response["message"]).to eq(expected_message)

        # Verify message contains required elements
        expect(expected_message).to include("🙏") # Emoji
        expect(expected_message).to include("gracias") # Gratitude (case insensitive)
        expect(expected_message).to include("reseña quedó registrada") # Confirmation
      end

      it "sends personalized comment request with provider name" do
        # Client selects rating
        response = Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "5"
        )

        # Verify message includes provider name
        expect(response["message"]).to match(/#{provider.name}/)
      end
    end

    context "when testing Requirement 14 compliance" do
      it "uses List Message instead of Quick Reply Buttons" do
        ReviewRequestJob.new.perform(job.id)

        # Verify List Message was sent (not buttons)
        expect(WhatsAppService).to have_received(:send_list_message)
        expect(WhatsAppService).not_to have_received(:send_message_with_buttons)
      end

      it "stores numeric value (1-5) in Review.rating field" do
        # Set up conversation with rating already collected
        conversation.update!(
          context: {
            "review_collection" => {
              "stage" => "awaiting_comment",
              "job_id" => job.id,
              "rating" => 4
            }
          }
        )

        # Client sends comment
        Assistants::ReviewCollectionService.call(
          provider: provider,
          client: client,
          conversation: conversation,
          body: "Buen trabajo"
        )

        # Verify numeric value stored in database
        review = Review.last
        expect(review.rating).to eq(4)
        expect(review.rating).to be_a(Integer)
      end

      it "applies same behavior for initial request and retry" do
        # First attempt
        ReviewRequestJob.new.perform(job.id)

        # Count how many times send_list_message was called
        first_call_count = 0
        allow(WhatsAppService).to receive(:send_list_message) do |args|
          first_call_count += 1
          payload = args[:payload]
          expect(payload[:type]).to eq("list")
          expect(payload[:action][:sections][0][:rows].length).to eq(5)
        end

        job.reload
        expect(job.review_attempts).to eq(1)

        # Simulate time passing and retry
        travel 1.day do
          ReviewRequestJob.new.perform(job.id)

          # Verify same List Message format is used for retry
          expect(first_call_count).to eq(1)

          job.reload
          expect(job.review_attempts).to eq(2)
        end
      end
    end
  end
end
