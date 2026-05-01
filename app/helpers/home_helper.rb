# frozen_string_literal: true

module HomeHelper
  # Maps category slugs to Material Symbols icon names (from Stitch design)
  CATEGORY_ICONS = {
    "fontanero" => "plumbing",
    "electricista" => "bolt",
    "carpintero" => "carpenter",
    "albanil" => "construction",
    "pintor" => "format_paint",
    "aire-acondicionado" => "air",
    "cerrajero" => "lock",
    "decorador" => "design_services",
    "limpieza" => "cleaning_services",
    "refrigeracion" => "kitchen"
  }.freeze

  # Formats a large number with comma separators for trust metrics display
  # e.g. 1500 → "1,500"
  def formatted_metric(number)
    number_with_delimiter(number)
  end

  # Builds the WhatsApp onboarding link for the #unete section
  def whatsapp_onboarding_link
    phone = ENV.fetch("TRATO_WHATSAPP_NUMBER", "")
    "https://wa.me/#{phone}?text=Quiero%20registrarme%20como%20t%C3%A9cnico"
  end

  # Returns the Material Symbols icon name for a category slug
  def category_icon_for(slug)
    CATEGORY_ICONS.fetch(slug, "home_repair_service")
  end
end
