# frozen_string_literal: true

require_relative 'data_models'
require_relative 'errors'

module ElisaAudit
  # Service to analyze placeholder naming consistency across all messages
  #
  # This service scans all messages for placeholder names (%{name}, %{provider_name}, %{ciudad},
  # %{phone}, etc.) and identifies inconsistencies in naming across flows.
  #
  # Purpose:
  #   Ensure placeholder names are consistent across all messages to prevent interpolation errors
  #   and make the codebase more maintainable.
  #
  # Usage:
  #   analyzer = ElisaAudit::PlaceholderConsistencyAnalyzer.new(message_entries)
  #   result = analyzer.call
  #
  #   # Result is a hash with:
  #   # {
  #   #   all_placeholders: { 'name' => 15, 'ciudad' => 8, ... },
  #   #   inconsistencies: [
  #   #     { concept: 'provider_name', variants: ['name', 'provider_name', 'nombre_provider'], ... }
  #   #   ],
  #   #   recommendations: ["Standardize provider name to 'provider_name'", ...],
  #   #   has_issues: true/false
  #   # }
  #
  # Requirements:
  #   - Req 30.1: Verify provider name is referenced consistently
  #   - Req 30.2: Verify city references use consistent placeholder
  #   - Req 30.3: Verify phone numbers use consistent placeholder
  #   - Req 30.4: Document any placeholder name inconsistencies found
  #   - Req 30.5: Recommend standardization if inconsistencies exist
  #   - Req 30.6: List all unique placeholder names in audit report
  class PlaceholderConsistencyAnalyzer
    # Known placeholder concepts and their common variants
    # Used to detect inconsistencies in naming conventions
    PLACEHOLDER_CONCEPTS = {
      provider_name: %w[name nombre provider_name provider nombre_provider proveedor],
      client_name: %w[client cliente client_name cliente_name nombre_cliente],
      city: %w[ciudad city ciudad_name city_name],
      zone: %w[zona zone area colonia neighborhood],
      phone: %w[phone teléfono telefono phone_number numero_telefono],
      provider_phone: %w[provider_phone phone_provider teléfono_provider telefono_provider],
      date: %w[date fecha fecha_date],
      time: %w[time hora time_hora horario],
      datetime: %w[datetime fecha_hora fechahora],
      price: %w[price precio monto amount],
      address: %w[address dirección direccion domicilio],
      email: %w[email correo correo_electronico],
      trade: %w[trade oficio profession profesion category categoria],
      work_type: %w[work_type tipo_trabajo type_work trabajo]
    }.freeze

    # Initialize analyzer with message entries
    # @param message_entries [Array<MessageEntry>] All messages from YAML inventory
    def initialize(message_entries)
      @message_entries = message_entries
      @all_placeholders = Hash.new(0)
      @inconsistencies = []
      @recommendations = []
    end

    # Main entry point - analyzes placeholder consistency
    # @return [Hash] Analysis results with placeholders, inconsistencies, and recommendations
    def call
      collect_all_placeholders
      detect_inconsistencies
      generate_recommendations

      {
        all_placeholders: @all_placeholders,
        inconsistencies: @inconsistencies,
        recommendations: @recommendations,
        has_issues: @inconsistencies.any?
      }
    end

    # Generate markdown report section for placeholder consistency analysis
    # @return [String] Markdown-formatted analysis report
    def generate_markdown_report
      output = []

      output << "## Placeholder Consistency Analysis"
      output << ""

      if @inconsistencies.empty?
        output << "✅ **No se encontraron inconsistencias en los nombres de placeholders.**"
        output << ""
        output << "Todos los placeholders siguen convenciones consistentes."
      else
        output << "⚠️ **Se encontraron #{@inconsistencies.count} inconsistencias en nombres de placeholders.**"
        output << ""

        # Show all unique placeholders
        output << "### Placeholders Encontrados"
        output << ""
        output << "Total de placeholders únicos: **#{@all_placeholders.count}**"
        output << ""
        output << "| Placeholder | Frecuencia |"
        output << "|-------------|------------|"

        @all_placeholders.sort_by { |k, v| [-v, k] }.each do |placeholder, count|
          output << "| `%{#{placeholder}}` | #{count} |"
        end
        output << ""

        # Show inconsistencies
        output << "### Inconsistencias Detectadas"
        output << ""

        @inconsistencies.each_with_index do |inconsistency, index|
          output << "#### #{index + 1}. #{inconsistency[:concept].to_s.titleize}"
          output << ""
          output << "**Variantes encontradas:**"
          output << ""

          inconsistency[:variants].each do |variant|
            count = @all_placeholders[variant]
            examples = inconsistency[:examples][variant] || []
            output << "- `%{#{variant}}` (usado #{count} veces)"

            if examples.any?
              example_list = examples.first(2).map { |e| "`#{e[:yaml_key]}`" }.join(', ')
              output << "  - Ejemplos: #{example_list}"
            end
          end
          output << ""
        end

        # Show recommendations
        output << "### Recomendaciones de Estandarización"
        output << ""

        if @recommendations.any?
          @recommendations.each_with_index do |recommendation, index|
            output << "#{index + 1}. #{recommendation}"
          end
        else
          output << "No hay recomendaciones específicas en este momento."
        end
        output << ""
      end

      output.join("\n")
    end

    private

    # Collect all placeholders from all messages
    # Counts frequency of each unique placeholder name
    def collect_all_placeholders
      @message_entries.each do |entry|
        next unless entry.has_variables?

        entry.variables.each do |variable|
          @all_placeholders[variable] += 1
        end
      end
    end

    # Detect inconsistencies by grouping similar placeholders
    # Compares actual placeholders against known concept variants
    def detect_inconsistencies
      PLACEHOLDER_CONCEPTS.each do |concept, known_variants|
        # Find which variants from this concept are actually used
        used_variants = @all_placeholders.keys.select do |placeholder|
          known_variants.include?(placeholder.downcase)
        end

        # If multiple variants are used for the same concept, it's an inconsistency
        next unless used_variants.count > 1

        # Collect examples for each variant
        examples = collect_examples_for_variants(used_variants)

        @inconsistencies << {
          concept: concept,
          variants: used_variants,
          examples: examples
        }
      end
    end

    # Collect example usages for each variant
    # @param variants [Array<String>] Placeholder variants to find examples for
    # @return [Hash] Map of variant to array of example entries
    def collect_examples_for_variants(variants)
      examples = Hash.new { |h, k| h[k] = [] }

      @message_entries.each do |entry|
        next unless entry.has_variables?

        entry.variables.each do |variable|
          if variants.include?(variable)
            examples[variable] << {
              flow_id: entry.flow_id,
              yaml_key: entry.yaml_key,
              content: entry.content.truncate(60)
            }
          end
        end
      end

      examples
    end

    # Generate recommendations for standardizing placeholders
    # Suggests which variant to use based on frequency and convention
    def generate_recommendations
      @inconsistencies.each do |inconsistency|
        concept = inconsistency[:concept]
        variants = inconsistency[:variants]

        # Determine the most common variant
        most_common = variants.max_by { |v| @all_placeholders[v] }

        # Determine the most conventional variant (prefer English, snake_case)
        most_conventional = select_most_conventional_variant(variants, concept)

        # Recommend the most common variant, or the most conventional if there's a tie
        recommended = if @all_placeholders[most_common] > @all_placeholders[most_conventional] * 1.5
                        most_common
                      else
                        most_conventional
                      end

        # Generate recommendation text
        other_variants = variants - [recommended]
        recommendation = "**#{concept.to_s.titleize}:** Estandarizar a `%{#{recommended}}` "
        recommendation += "(usado #{@all_placeholders[recommended]} veces). "
        recommendation += "Reemplazar: #{other_variants.map { |v| "`%{#{v}}`" }.join(', ')}"

        @recommendations << recommendation
      end
    end

    # Select the most conventional variant from a list
    # Prefers English, snake_case, and common Rails conventions
    # @param variants [Array<String>] Placeholder variants
    # @param concept [Symbol] The concept being represented
    # @return [String] The most conventional variant
    def select_most_conventional_variant(variants, concept)
      # Define conventional names for each concept
      conventional_names = {
        provider_name: 'provider_name',
        client_name: 'client_name',
        city: 'ciudad',  # Spanish is conventional in this context
        zone: 'zona',    # Spanish is conventional
        phone: 'phone',
        provider_phone: 'provider_phone',
        date: 'fecha',   # Spanish conventional
        time: 'hora',    # Spanish conventional
        datetime: 'fecha_hora',
        price: 'monto',  # Spanish conventional
        address: 'direccion',
        email: 'email',
        trade: 'oficio', # Spanish conventional
        work_type: 'tipo_trabajo'
      }

      preferred = conventional_names[concept]

      # Return preferred if it's in the variants, otherwise return first variant
      variants.include?(preferred) ? preferred : variants.first
    end
  end
end
