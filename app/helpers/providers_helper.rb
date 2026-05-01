# frozen_string_literal: true

module ProvidersHelper
  # Extracts specialty tags from the provider's work photos category_tags.
  # Falls back to secondary category names if no tags exist.
  def extract_specialties(provider, categories)
    tags_from_photos = provider.photos
                               .where.not(category_tags: nil)
                               .pluck(:category_tags)
                               .flatten
                               .uniq

    return tags_from_photos if tags_from_photos.any?

    categories.reject(&:primary?).map(&:name)
  end

  # Formats the member_since date in Spanish (e.g. "Enero 2025")
  def formatted_member_since(date)
    return "" unless date

    month_names = %w[Enero Febrero Marzo Abril Mayo Junio Julio Agosto Septiembre Octubre Noviembre Diciembre]
    "#{month_names[date.month - 1]} #{date.year}"
  end

  # Formats a price in MXN (e.g. "$300 MXN")
  def formatted_price(price)
    return nil unless price&.positive?

    "$#{price.to_i} MXN"
  end

  # Returns initials for avatar placeholder when no profile photo exists
  def provider_initials(name)
    return "?" if name.blank?

    name.split.filter_map { |word| word[0] }.first(2).join.upcase
  end

  # Relative time description in Spanish
  def time_ago_in_spanish(date)
    return "" unless date

    days = ((Time.current - date.to_time) / 86_400).to_i

    case days
    when 0 then "Hoy"
    when 1 then "Hace 1 día"
    when 2..6 then "Hace #{days} días"
    when 7..13 then "Hace 1 semana"
    when 14..29 then "Hace #{days / 7} semanas"
    when 30..59 then "Hace 1 mes"
    when 60..364 then "Hace #{days / 30} meses"
    when 365..729 then "Hace 1 año"
    else "Hace #{days / 365} años"
    end
  end

  # Renders filled star icons using Material Symbols style (matching Stitch design)
  # Returns HTML-safe string of star SVGs colored with secondary (#FEA619)
  def filled_stars(count, size: "sm")
    safe_join(Array.new([count, 5].min) { star_filled_svg(size) })
  end

  private

  def star_filled_svg(size)
    css_class = size == "sm" ? "w-4 h-4" : "w-5 h-5"
    tag.svg(xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 24 24", fill: "currentColor",
            class: "#{css_class} text-[#FEA619] inline-block") do
      tag.path(fill_rule: "evenodd",
               d: "M10.788 3.21c.448-1.077 1.976-1.077 2.424 0l2.082 5.006 5.404.434c1.164.093 1.636 1.545.749 2.305l-4.117 3.527 1.257 5.273c.271 1.136-.964 2.033-1.96 1.425L12 18.354 7.373 21.18c-.996.608-2.231-.29-1.96-1.425l1.257-5.273-4.117-3.527c-.887-.76-.415-2.212.749-2.305l5.404-.434 2.082-5.005Z",
               clip_rule: "evenodd")
    end
  end
end
