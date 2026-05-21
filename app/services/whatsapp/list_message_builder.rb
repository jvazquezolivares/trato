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
      price_ranges = [
        { id: "100-200", title: "$100–200 MXN" },
        { id: "200-400", title: "$200–400 MXN" },
        { id: "400-600", title: "$400–600 MXN" },
        { id: "600+", title: "Más de $600 MXN" }
      ]

      {
        type: "list",
        header: {
          type: "text",
          text: "Rango de precio"
        },
        body: {
          text: "¿Cuánto cobras por una visita de diagnóstico?"
        },
        action: {
          button: "Ver opciones",
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
      experience_ranges = [
        { id: "1-3", title: "1–3 años" },
        { id: "4-6", title: "4–6 años" },
        { id: "7-10", title: "7–10 años" },
        { id: "10+", title: "Más de 10 años" }
      ]

      {
        type: "list",
        header: {
          type: "text",
          text: "Años de experiencia"
        },
        body: {
          text: "¿Cuántos años llevas trabajando en tu oficio?"
        },
        action: {
          button: "Ver opciones",
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
      decline_reasons = [
        { id: "busy", title: "Estoy muy ocupado" },
        { id: "dont_understand", title: "No entiendo qué es" },
        { id: "not_worth_it", title: "No sé si vale pena" },
        { id: "uncomfortable_whatsapp", title: "No me gusta WhatsApp" },
        { id: "enough_clients", title: "Tengo suficientes" },
        { id: "other", title: "Otro motivo" }
      ]

      {
        type: "list",
        header: {
          type: "text",
          text: "¿Por qué no por ahora?"
        },
        body: {
          text: "Me ayudaría saber qué te detiene"
        },
        action: {
          button: "Ver opciones",
          sections: [
            {
              title: "Razón",
              rows: decline_reasons.map do |reason|
                { id: reason[:id], title: truncate_label(reason[:title]) }
              end
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
      financial_options = [
        { id: "income", title: "Ver ingresos" },
        { id: "expenses", title: "Ver gastos" },
        { id: "pending", title: "Ver cobros" },
        { id: "no_thanks", title: "No, gracias" }
      ]

      {
        type: "list",
        header: {
          type: "text",
          text: "¿Qué quieres ver?"
        },
        body: {
          text: "Puedo mostrarte un resumen de tus finanzas"
        },
        action: {
          button: "Ver opciones",
          sections: [
            {
              title: "Opciones financieras",
              rows: financial_options.map do |option|
                { id: option[:id], title: truncate_label(option[:title]) }
              end
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
      ratings = [
        { id: "5", title: "⭐⭐⭐⭐⭐ Excelente" },
        { id: "4", title: "⭐⭐⭐⭐ Muy bueno" },
        { id: "3", title: "⭐⭐⭐ Bueno" },
        { id: "2", title: "⭐⭐ Regular" },
        { id: "1", title: "⭐ Malo" }
      ]

      {
        type: "list",
        header: {
          type: "text",
          text: "¿Cómo calificarías el trabajo?"
        },
        body: {
          text: "Tu opinión ayuda a otros clientes"
        },
        action: {
          button: "Ver opciones",
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
  end
end
