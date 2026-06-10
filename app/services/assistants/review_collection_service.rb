# frozen_string_literal: true

module Assistants
  # Handles the review collection flow when a client responds to a
  # ReviewRequestJob message with a numeric rating (1–5).
  #
  # Flow:
  #   1. Client sends a number 1–5 → store rating in conversation context,
  #      ask for optional comment
  #   2. Client sends comment (or skips) → create Review with verified: true
  #
  # The conversation context tracks the review collection stage:
  #   context["review_collection"] = {
  #     "stage" => "awaiting_rating" | "awaiting_comment",
  #     "job_id" => 123,
  #     "rating" => 4
  #   }
  #
  # Usage:
  #   Assistants::ReviewCollectionService.call(
  #     provider: provider, client: client,
  #     conversation: conversation, body: "5"
  #   )
  class ReviewCollectionService
    def self.call(provider:, client:, conversation:, body:)
      new(
        provider: provider, client: client,
        conversation: conversation, body: body
      ).process
    end

    # Detects if the current conversation is in a review collection stage.
    #
    # @param conversation [Conversation] the conversation to check
    # @return [Boolean]
    def self.collecting_review?(conversation)
      review_context = conversation.context&.dig("review_collection")
      return false unless review_context

      %w[awaiting_rating awaiting_comment].include?(review_context["stage"])
    end

    # Detects if a message body looks like a review rating (1–5).
    # Used to detect unsolicited ratings from clients who received a
    # ReviewRequestJob message.
    #
    # @param body [String] the message body
    # @param conversation [Conversation] the conversation to check for pending reviews
    # @return [Boolean]
    def self.review_rating?(body:, conversation:)
      return false unless body.present?

      stripped = body.to_s.strip
      return false unless stripped.match?(/\A[1-5]\z/)

      # Check if there's a pending review job for this conversation's client
      has_pending_review_job?(conversation)
    end

    def initialize(provider:, client:, conversation:, body:)
      @provider = provider
      @client = client
      @conversation = conversation
      @body = body.to_s.strip
    end

    def process
      review_context = @conversation.context&.dig("review_collection") || {}
      stage = review_context["stage"]

      case stage
      when "awaiting_comment"
        handle_comment(review_context)
      when "awaiting_rating"
        handle_rating
      else
        # First interaction — client sent a rating number
        handle_rating
      end
    end

    private

    # Handles a numeric rating (1–5) from the client.
    # Accepts both direct numeric input and List Message selection IDs.
    # Stores the rating and asks for an optional comment.
    def handle_rating
      rating = extract_rating_value
      return invalid_rating_response unless rating.between?(1, 5)

      job = find_reviewable_job
      return no_job_response unless job

      update_review_context(
        "stage" => "awaiting_comment",
        "job_id" => job.id,
        "rating" => rating
      )

      rating_ack = I18n.t("elisa.client.review.rating_ack", rating: rating)
      comment_request = I18n.t("elisa.client.review.comment_request", name: @provider.name)

      build_response(
        message: "#{rating_ack} #{comment_request}",
        should_save: false,
        intent: nil
      )
    end

    # Handles the optional comment after a rating was given.
    # Creates the Review record and marks the job as reviewed.
    def handle_comment(review_context)
      job_id = review_context["job_id"]
      rating = review_context["rating"]

      job = Job.find_by(id: job_id)
      return no_job_response unless job

      comment = extract_comment
      create_review(job: job, rating: rating, comment: comment)
      mark_job_reviewed(job)
      clear_review_context

      build_response(
        message: I18n.t("elisa.client.review.completion"),
        should_save: true,
        intent: "review_collected"
      )
    end

    # Extracts the comment from the body, treating "no" as no comment.
    def extract_comment
      return nil if MessagePersistenceFilter.trivial_body?(@body)

      @body
    end

    # Extracts the rating value from the message body.
    # Handles both direct numeric input ("5") and List Message selection IDs ("5").
    # Since List Message IDs are already numeric strings, this method simply
    # converts to integer and validates the range.
    #
    # @return [Integer] the rating value (1-5)
    def extract_rating_value
      @body.to_i
    end

    # Creates a verified Review record.
    def create_review(job:, rating:, comment:)
      Review.create!(
        provider: @provider,
        client: @client,
        job: job,
        rating: rating,
        comment: comment,
        verified: true
      )
    end

    # Marks the job as having received a review.
    def mark_job_reviewed(job)
      job.update!(review_sent: true)
    end

    # Finds a job eligible for review (paid or partial, not yet reviewed).
    def find_reviewable_job
      Job.where(
        provider: @provider,
        client: @client,
        review_sent: false
      ).where(status: %w[paid partial])
       .order(created_at: :desc)
       .first
    end

    # Updates the review collection context on the conversation.
    def update_review_context(data)
      context = @conversation.context || {}
      context["review_collection"] = data
      @conversation.update!(context: context)
    end

    # Clears the review collection context.
    def clear_review_context
      context = @conversation.context || {}
      context.delete("review_collection")
      @conversation.update!(context: context)
    end

    # Builds a standardized response hash matching ClaudeService format.
    def build_response(message:, should_save:, intent:)
      {
        "message" => message,
        "action" => "none",
        "action_data" => {},
        "new_stage" => nil,
        "updated_context" => {},
        "should_save_message" => should_save,
        "intent" => intent
      }
    end

    def invalid_rating_response
      build_response(
        message: I18n.t("elisa.client.review.invalid_rating_error"),
        should_save: false,
        intent: nil
      )
    end

    def no_job_response
      build_response(
        message: "No encontré un trabajo pendiente de reseña. ¡Gracias de todas formas! 😊",
        should_save: false,
        intent: nil
      )
    end

    # Checks if there's a pending review for the conversation's client.
    def self.has_pending_review_job?(conversation)
      return false unless conversation.client_id.present? && conversation.provider_id.present?

      Job.where(
        provider_id: conversation.provider_id,
        client_id: conversation.client_id,
        review_sent: false
      ).where(status: %w[paid partial])
       .exists?
    end

    private_class_method :has_pending_review_job?
  end
end
