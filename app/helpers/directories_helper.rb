# frozen_string_literal: true

module DirectoriesHelper
  # Returns the first work photo for a provider, or nil if none exist
  def first_work_photo(provider)
    provider.photos.reject(&:profile_photo?).first
  end

  # Returns the profile photo for a provider, or nil
  def profile_photo_for(provider)
    provider.photos.find(&:profile_photo?)
  end

  # Returns the primary category for a provider
  def primary_category_for(provider)
    provider.provider_categories.find(&:primary?)
  end

  # Calculates average rating from loaded reviews (avoids extra query)
  def average_rating_for(provider)
    verified = provider.reviews.select(&:verified?)
    return 0.0 if verified.empty?

    (verified.sum(&:rating).to_f / verified.size).round(1)
  end

  # Returns the count of verified reviews
  def review_count_for(provider)
    provider.reviews.count(&:verified?)
  end

  # Extracts specialty tags from photos or falls back to secondary categories
  def specialties_for(provider)
    tags = provider.photos
                   .reject { |p| p.category_tags.blank? }
                   .flat_map(&:category_tags)
                   .uniq
                   .first(3)

    return tags if tags.any?

    provider.provider_categories
            .reject(&:primary?)
            .map(&:name)
            .first(3)
  end

  # Returns the total jobs count from loaded association
  def jobs_count_for(provider)
    provider.jobs.size
  end

  # Builds the directory filter URL preserving the category_city param
  def directory_filter_path(category_city, filter_value)
    if filter_value.present?
      category_directory_path(category_city: category_city, filter: filter_value)
    else
      category_directory_path(category_city: category_city)
    end
  end

  # Returns CSS classes for filter chip based on active state
  def filter_chip_classes(current_filter, chip_filter)
    if current_filter == chip_filter
      "bg-[#005C55] text-white px-6 py-2.5 rounded-full font-bold text-sm shadow-md transition-all"
    else
      "bg-[#F0F3FF] text-[#111C2D] hover:bg-[#DEE8FF] px-6 py-2.5 rounded-full font-semibold text-sm transition-all"
    end
  end

  # Humanizes the city name from parameterized URL segment
  def humanize_city(city_param)
    city_param.tr("-", " ").split.map(&:capitalize).join(" ")
  end
end
