# frozen_string_literal: true

# Loads all data needed to render the homepage.
# Keeps query logic out of controllers and views.
#
# Follows the same pattern as DirectoryService: returns self
# with attr_reader accessors for the view to consume.
class HomepageService
  FEATURED_LIMIT = 6

  attr_reader :featured_providers, :total_providers, :total_jobs,
              :total_reviews, :categories

  def self.call
    new.call
  end

  def call
    load_featured_providers
    load_trust_metrics
    load_categories
    self
  end

  private

  # Fetches up to 6 featured providers: active, with at least one work photo.
  # Eager-loads associations to avoid N+1 queries in the view.
  #
  # Two-step query (same approach as DirectoryService) to avoid
  # PG::InvalidColumnReference with DISTINCT + ORDER BY on columns
  # not in the SELECT list.
  def load_featured_providers
    # Step 1: get matching IDs (no ORDER BY conflict with DISTINCT)
    matching_ids = Provider
      .where(active: true)
      .joins(:photos)
      .where(photos: { profile_photo: false })
      .distinct
      .pluck(:id)

    # Step 2: order and limit from the clean ID set
    featured_ids = Provider
      .where(id: matching_ids)
      .order(created_at: :desc)
      .limit(FEATURED_LIMIT)
      .pluck(:id)

    @featured_providers = if featured_ids.empty?
                            Provider.none
    else
                            Provider
                              .where(id: featured_ids)
                              .includes(:provider_categories, :photos, :reviews, :jobs)
                              .order(Arel.sql("ARRAY_POSITION(ARRAY[#{featured_ids.join(',')}], providers.id)"))
    end
  end

  def load_trust_metrics
    @total_providers = Provider.where(active: true).count
    @total_jobs = Job.count
    @total_reviews = Review.where(verified: true).count
  end

  # Returns distinct primary categories from active providers.
  # Uses a Struct instead of OpenStruct for better performance and explicitness.
  def load_categories
    @categories = ProviderCategory
      .joins(:provider)
      .where(providers: { active: true })
      .where(primary: true)
      .select(:name, :slug)
      .distinct
  end
end
