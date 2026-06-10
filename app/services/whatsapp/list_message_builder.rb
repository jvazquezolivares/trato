# frozen_string_literal: true

module WhatsApp
  # Generates WhatsApp List Message payloads for Meta Cloud API.
  # All responses are deterministic (no AI interpretation).
  # List Messages support 4+ options, unlike Quick Reply Buttons (max 3).
  class ListMessageBuilder
    # Maximum character limit for List Message button labels per Meta Cloud API
    MAX_BUTTON_LABEL_LENGTH = 20

    # Builds a List Message with zones for client discovery flow.
    #
    # @param zones [Array<String>] Array of zone names
    # @param title [String] Header text for the message
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_zones_list(zones, title: "Selecciona tu zona")
      {
        type: "list",
        header: {
          type: "text",
          text: title
        },
        body: {
          text: "Elige la zona donde necesitas el servicio"
        },
        action: {
          button: "Ver opciones",
          sections: [
            {
              title: "Zonas disponibles",
              rows: zones.map { |zone| { id: zone, title: truncate_label(zone) } }
            }
          ]
        }
      }
    end

    # Builds a List Message with service categories.
    # Page 1 shows first 5 categories + "Ver más categorías" option.
    # Page 2 shows remaining categories.
    #
    # @param page [Integer] Page number (1 or 2)
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_categories_list(page: 1)
      categories = ZonesService.categories_page(page)

      rows = categories.map do |cat|
        {
          id: cat["id"],
          title: truncate_label("#{cat['icon']} #{cat['name']}")
        }
      end

      # Add "Ver más categorías" option on page 1 if there are more categories
      if page == 1 && ZonesService.all_categories.length > 5
        rows << {
          id: "ver_mas_categorias",
          title: "Ver más categorías"
        }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: "¿Qué tipo de técnico?"
        },
        body: {
          text: "Selecciona el servicio que necesitas"
        },
        action: {
          button: "Ver opciones",
          sections: [
            {
              title: "Categorías",
              rows: rows
            }
          ]
        }
      }
    end

    # Builds a List Message with diagnosis visit price ranges.
    # Used in provider onboarding flow (P4).
    #
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_price_range_list
      options = I18n.t("elisa.provider.list_messages.price_range.options")
      price_range_ids = ["100-200", "200-400", "400-600", "600+"]

      price_ranges = options.map.with_index do |title, index|
        { id: price_range_ids[index], title: title }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: I18n.t("elisa.provider.list_messages.price_range.title")
        },
        body: {
          text: I18n.t("elisa.provider.list_messages.price_range.body")
        },
        action: {
          button: I18n.t("elisa.provider.list_messages.price_range.button"),
          sections: [
            {
              title: "Precio de diagnóstico",
              rows: price_ranges
            }
          ]
        }
      }
    end

    # Builds a List Message with years of experience ranges.
    # Used in provider onboarding flow (P5).
    #
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_experience_range_list
      options = I18n.t("elisa.provider.list_messages.experience.options")
      experience_range_ids = ["1-3", "4-6", "7-10", "10+"]

      experience_ranges = options.map.with_index do |title, index|
        { id: experience_range_ids[index], title: title }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: I18n.t("elisa.provider.list_messages.experience.title")
        },
        body: {
          text: I18n.t("elisa.provider.list_messages.experience.body")
        },
        action: {
          button: I18n.t("elisa.provider.list_messages.experience.button"),
          sections: [
            {
              title: "Experiencia",
              rows: experience_ranges
            }
          ]
        }
      }
    end

    # Builds a List Message with decline reasons.
    # Used when provider responds "Mejor después" during onboarding (P1B).
    #
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_decline_reasons_list
      options = I18n.t("elisa.provider.list_messages.decline_reasons.options")
      decline_reason_ids = ["busy", "dont_understand", "not_worth_it", "uncomfortable_whatsapp", "enough_clients", "other"]

      decline_reasons = options.map.with_index do |title, index|
        { id: decline_reason_ids[index], title: truncate_label(title) }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: I18n.t("elisa.provider.list_messages.decline_reasons.title")
        },
        body: {
          text: I18n.t("elisa.provider.list_messages.decline_reasons.body")
        },
        action: {
          button: I18n.t("elisa.provider.list_messages.decline_reasons.button"),
          sections: [
            {
              title: "Razón",
              rows: decline_reasons
            }
          ]
        }
      }
    end

    # Builds a List Message with financial summary options.
    # Used in provider flows (P17).
    #
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_financial_options_list
      options = I18n.t("elisa.provider.list_messages.financial_summary.options")
      financial_option_ids = ["income", "expenses", "pending", "no_thanks"]

      financial_options = options.map.with_index do |title, index|
        { id: financial_option_ids[index], title: truncate_label(title) }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: I18n.t("elisa.provider.list_messages.financial_summary.title")
        },
        body: {
          text: I18n.t("elisa.provider.list_messages.financial_summary.body")
        },
        action: {
          button: I18n.t("elisa.provider.list_messages.financial_summary.button"),
          sections: [
            {
              title: "Opciones financieras",
              rows: financial_options
            }
          ]
        }
      }
    end

    # Builds a List Message with star rating options.
    # Used in review collection flow (C7A).
    #
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_rating_list
      options = I18n.t("elisa.client.list_messages.ratings.options")
      rating_ids = ["5", "4", "3", "2", "1"]

      ratings = options.map.with_index do |title, index|
        { id: rating_ids[index], title: title }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: I18n.t("elisa.client.list_messages.ratings.title")
        },
        body: {
          text: I18n.t("elisa.client.list_messages.ratings.body")
        },
        action: {
          button: I18n.t("elisa.client.list_messages.ratings.button"),
          sections: [
            {
              title: "Calificación",
              rows: ratings
            }
          ]
        }
      }
    end

    # Builds a List Message with primary trade selection options.
    # Used in provider onboarding flow (P2B) when provider has multiple categories.
    #
    # @param categories [Array<String>] Array of category names
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_primary_trade_list(categories)
      # Build rows for each category
      category_rows = categories.map.with_index do |category, index|
        { id: "category_#{index}", title: truncate_label(category) }
      end

      # Add "all equal frequency" option
      category_rows << {
        id: "all_equal",
        title: "Todos igual frec."
      }

      {
        type: "list",
        header: {
          type: "text",
          text: "Oficio principal"
        },
        body: {
          text: "¿Cuál haces con más frecuencia?"
        },
        action: {
          button: "Ver opciones",
          sections: [
            {
              title: "Selecciona uno",
              rows: category_rows
            }
          ]
        }
      }
    end

    # Builds a List Message with provider search results.
    # Used in client discovery flow (C2A) after zone and category selection.
    # Displays max 10 providers per page with "Ver más" option if more results exist.
    #
    # @param providers [ActiveRecord::Relation] Provider query results
    # @param page [Integer] Page number (default: 1)
    # @param zone [String] Selected zone name
    # @param category [String] Selected category name
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_provider_results_list(providers, page: 1, zone:, category:)
      # Paginate results (10 per page)
      per_page = 10
      offset = (page - 1) * per_page
      total_count = providers.count
      paginated_providers = providers.offset(offset).limit(per_page)

      # Build rows for each provider
      provider_rows = paginated_providers.map do |provider|
        # Calculate average rating
        avg_rating = provider.reviews.average(:rating)
        rating_display = avg_rating ? "⭐ #{avg_rating.round(1)}" : "Sin reseñas"

        # Build title with name and rating (max 20 chars)
        title = truncate_label("#{provider.name} #{rating_display}")

        # Build description with primary category and city
        primary_category = provider.provider_categories.find_by(primary: true)
        category_name = primary_category&.name || "Técnico"
        description = "#{category_name} • #{provider.city}"

        {
          id: "provider_#{provider.id}",
          title: title,
          description: truncate_description(description)
        }
      end

      # Add "Ver más" option if there are more results
      has_more = total_count > (page * per_page)
      if has_more
        provider_rows << {
          id: "ver_mas_providers_page_#{page + 1}",
          title: "Ver más técnicos",
          description: "Mostrar más resultados"
        }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: "Técnicos disponibles"
        },
        body: {
          text: "Encontré #{total_count} técnico#{'s' if total_count != 1} de #{category} en #{zone}"
        },
        action: {
          button: "Ver opciones",
          sections: [
            {
              title: "Selecciona uno",
              rows: provider_rows
            }
          ]
        }
      }
    end

    # Truncates label to MAX_BUTTON_LABEL_LENGTH characters.
    # Meta Cloud API enforces 20-character limit for button labels.
    #
    # @param label [String] Original label text
    # @return [String] Truncated label if necessary
    def self.truncate_label(label)
      return label if label.length <= MAX_BUTTON_LABEL_LENGTH

      "#{label[0...MAX_BUTTON_LABEL_LENGTH - 1]}…"
    end
    private_class_method :truncate_label

    # Builds a List Message with available appointment time slots.
    # Used in client appointment scheduling flow (C1A) when WorkDay exists.
    #
    # @param slots [Array<Hash>] Array of slot hashes with :time and :display_time
    # @param date [Date] The date for the available slots
    # @param provider_name [String] The provider's name
    # @return [Hash] List Message payload for Meta Cloud API
    def self.build_available_slots_list(slots, date:, provider_name:)
      # Format date for display (e.g., "mañana" or "jueves 21 de mayo")
      date_display = if date == Date.tomorrow
                       "mañana"
      else
                       date.strftime("%A %d de %B").downcase
      end

      # Format header title based on date
      header_title = if date == Date.tomorrow
                       "Horarios disponibles — mañana"
      else
                       "Horarios disponibles — #{date_display}"
      end

      # Build rows for each available slot
      slot_rows = slots.map do |slot|
        {
          id: "slot_#{slot[:time].to_i}", # Unix timestamp as unique ID
          title: slot[:display_time] # e.g., "09:00"
        }
      end

      {
        type: "list",
        header: {
          type: "text",
          text: header_title
        },
        body: {
          text: "#{provider_name} tiene #{slots.count} horario#{'s' if slots.count != 1} disponible#{'s' if slots.count != 1} para #{date_display}"
        },
        action: {
          button: "Ver horarios",
          sections: [
            {
              title: "Selecciona un horario",
              rows: slot_rows
            }
          ]
        }
      }
    end

    # Truncates description to 72 characters (Meta Cloud API limit).
    #
    # @param description [String] Original description text
    # @return [String] Truncated description if necessary
    def self.truncate_description(description)
      max_length = 72
      return description if description.length <= max_length

      "#{description[0...max_length - 1]}…"
    end
    private_class_method :truncate_description
  end
end
