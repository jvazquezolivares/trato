# frozen_string_literal: true

module Assistants
  # Builds and sends review summaries for a provider.
  # Provides stats for system prompts and formatted WhatsApp messages.
  #
  # Usage:
  #   Assistants::ReviewSummaryService.call(provider: provider, to: "521...")
  #   Assistants::ReviewSummaryService.stats(provider: provider)
  #   # => { average: "4.5/5", count: 12 }
  class ReviewSummaryService
    def self.call(provider:, to:, send_profile_link: true)
      new(provider: provider, to: to, send_profile_link: send_profile_link).send_summary
    end

    def self.stats(provider:)
      new(provider: provider, to: nil).build_stats
    end

    def initialize(provider:, to:, send_profile_link: true)
      @provider = provider
      @to = to
      @send_profile_link = send_profile_link
    end

    def send_summary
      reviews = verified_reviews
      return if reviews.empty?

      WhatsAppService.send_message(to: @to, message: format_summary(reviews))
      send_profile_link if @send_profile_link
    end

    def build_stats
      reviews = verified_reviews
      count = reviews.count

      return { average: "Sin calificación aún", count: 0 } unless count.positive?

      average = reviews.average(:rating)&.round(1) || 0
      { average: "#{average}/5", count: count }
    end

    private

    def verified_reviews
      @provider.reviews.where(verified: true)
    end

    def format_summary(reviews)
      count = reviews.count
      average = reviews.average(:rating)&.round(1) || 0
      highlighted = reviews.order(created_at: :desc).limit(2)

      summary = "⭐ #{average}/5 — #{count} reseñas verificadas\n\n"

      highlighted.each do |review|
        stars = "⭐" * review.rating
        summary += "#{stars} #{review.comment&.truncate(100)}\n"
      end

      summary + "\nTodas las reseñas tienen el sello ✓ Verificado por Trato"
    end

    def send_profile_link
      profile_url = "trato.mx/p/#{@provider.slug}"
      WhatsAppService.send_message(to: @to, message: "Perfil completo: #{profile_url}")
    end
  end
end
