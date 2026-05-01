# frozen_string_literal: true

# Loads all data needed to render a provider's public profile page.
# Keeps query logic out of controllers and views.
class ProviderProfileService
  attr_reader :provider, :categories, :primary_category, :reviews,
              :work_photos, :profile_photo, :stats, :rating_distribution

  def initialize(provider)
    @provider = provider
  end

  def self.call(provider)
    new(provider).call
  end

  def call
    load_categories
    load_photos
    load_reviews
    build_stats
    build_rating_distribution
    self
  end

  private

  def load_categories
    @categories = provider.provider_categories.order(primary: :desc, name: :asc)
    @primary_category = @categories.find(&:primary?)
  end

  def load_photos
    photos = provider.photos.order(created_at: :desc)
    @profile_photo = photos.find(&:profile_photo?)
    @work_photos = photos.reject(&:profile_photo?)
  end

  def load_reviews
    @reviews = provider.reviews
                       .includes(:client)
                       .where(verified: true)
                       .order(created_at: :desc)
  end

  def build_stats
    total_jobs = provider.jobs.count
    member_since = provider.onboarded_at || provider.created_at

    @stats = {
      member_since: member_since,
      total_jobs: total_jobs,
      average_rating: average_rating,
      review_count: @reviews.size
    }
  end

  # Calculates percentage of reviews per star level (5 down to 1)
  # for the rating distribution bars in the reviews section
  def build_rating_distribution
    total = @reviews.size
    @rating_distribution = (1..5).reverse_each.map do |star|
      count = @reviews.count { |r| r.rating == star }
      percentage = total.positive? ? ((count.to_f / total) * 100).round : 0
      { star: star, count: count, percentage: percentage }
    end
  end

  def average_rating
    return 0.0 if @reviews.empty?

    (@reviews.sum(&:rating).to_f / @reviews.size).round(1)
  end
end
