# frozen_string_literal: true

# Loads all data needed to render a category directory page.
# Keeps query logic out of controllers and views.
#
# Parses the :category_city URL segment (e.g. "fontaneros-en-veracruz")
# into a category slug and city, then fetches matching providers with
# eager-loaded associations to avoid N+1 queries.
class DirectoryService
  PER_PAGE = 12

  attr_reader :category_slug, :city, :providers, :total_count,
              :page, :total_pages, :category_display_name

  def initialize(category_city:, page: 1, filter: nil)
    @category_city = category_city
    @page = [page.to_i, 1].max
    @filter = filter
  end

  def self.call(category_city:, page: 1, filter: nil)
    new(category_city: category_city, page: page, filter: filter).call
  end

  def call
    parse_category_city
    load_providers
    self
  end

  private

  def parse_category_city
    # URL format: "fontaneros-en-veracruz" → category_slug: "fontanero", city: "veracruz"
    # The category in the URL is pluralized; we singularize to match ProviderCategory.slug
    match = @category_city.match(/\A(.+)-en-(.+)\z/)
    raise ActiveRecord::RecordNotFound, "Invalid directory URL format" unless match

    @category_slug = match[1].singularize
    @city = match[2]
    @category_display_name = match[1].titleize
  end

  def load_providers
    # Step 1: Get matching provider IDs (avoids DISTINCT + ORDER BY conflicts)
    matching_ids = Provider
      .joins(:provider_categories)
      .where(active: true)
      .where(provider_categories: { slug: @category_slug })
      .where("LOWER(providers.city) = ?", @city.tr("-", " ").downcase)
      .distinct
      .pluck(:id)

    @total_count = matching_ids.size
    @total_pages = [(@total_count.to_f / PER_PAGE).ceil, 1].max

    # Step 2: Apply filter and ordering to get the final ordered IDs
    ordered_ids = apply_filter_and_order(matching_ids)

    # Step 3: Paginate the ordered IDs
    paginated_ids = ordered_ids.drop((@page - 1) * PER_PAGE).first(PER_PAGE)

    # Step 4: Load full records with eager-loaded associations, preserving order
    return @providers = Provider.none if paginated_ids.empty?

    @providers = Provider
      .where(id: paginated_ids)
      .includes(:provider_categories, :photos, :reviews, :jobs)
      .order(Arel.sql("ARRAY_POSITION(ARRAY[#{paginated_ids.join(',')}], providers.id)"))
  end

  def apply_filter_and_order(provider_ids)
    return provider_ids if provider_ids.empty?

    case @filter
    when "mejor-calificados"
      # Sort by average rating descending, unrated providers last
      rated = Provider
        .joins(:reviews)
        .where(id: provider_ids)
        .group("providers.id")
        .order("AVG(reviews.rating) DESC")
        .pluck(:id)

      unrated = provider_ids - rated
      rated + unrated
    when "con-fotos"
      Provider
        .joins(:photos)
        .where(id: provider_ids, photos: { profile_photo: false })
        .group("providers.id")
        .order("providers.created_at DESC")
        .pluck(:id)
    when "precio-bajo"
      Provider.where(id: provider_ids).order(base_price: :asc).pluck(:id)
    else
      Provider.where(id: provider_ids).order(created_at: :desc).pluck(:id)
    end
  end
end
