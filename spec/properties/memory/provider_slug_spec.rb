# frozen_string_literal: true

# Feature: trato-mvp, Property 5: Slug always matches expected format
# **Validates: Requirements 2.9**
#
# For any Provider with a name, primary category, city, and short_uuid,
# the slug SHALL always match the format:
# {primary_cat_plural}-en-{city_parameterized}/{name_parameterized}-{primary_cat}-{short_uuid}
# and SHALL always be URL-safe (no spaces, special chars except hyphens/slashes).

require "rails_helper"

RSpec.describe Provider, "P5: slug format", type: :property do
  context "when provider has all required fields" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "generates a slug matching the expected format (iteration #{iteration + 1})" do
        # Create a provider with a primary category
        provider = build_stubbed(:provider)
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true)

        # Allow the provider to find its primary category
        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        # Build the slug as the system would
        slug = provider.build_slug

        # 1. Slug must contain the primary category plural
        primary_cat_plural = primary_category.slug.pluralize
        expect(slug).to include(primary_cat_plural),
          "Expected slug to include primary category plural '#{primary_cat_plural}' but got '#{slug}'"

        # 2. Slug must contain "-en-"
        expect(slug).to include("-en-"),
          "Expected slug to include '-en-' separator but got '#{slug}'"

        # 3. Slug must contain the city (parameterized)
        city_param = provider.city.parameterize
        expect(slug).to include(city_param),
          "Expected slug to include city '#{city_param}' but got '#{slug}'"

        # 4. Slug must contain the name (parameterized)
        name_param = provider.name.parameterize
        expect(slug).to include(name_param),
          "Expected slug to include name '#{name_param}' but got '#{slug}'"

        # 5. Slug must contain the primary category slug
        expect(slug).to include(primary_category.slug),
          "Expected slug to include primary category slug '#{primary_category.slug}' but got '#{slug}'"

        # 6. Slug must contain the short_uuid
        expect(slug).to include(provider.short_uuid),
          "Expected slug to include short_uuid '#{provider.short_uuid}' but got '#{slug}'"
      end
    end
  end

  context "when slug format is validated" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "matches the exact pattern (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true)

        # Allow the provider to find its primary category
        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        # Build the expected pattern
        primary_cat_plural = primary_category.slug.pluralize
        city_param = provider.city.parameterize
        name_param = provider.name.parameterize
        primary_cat_slug = primary_category.slug

        expected_pattern = "#{primary_cat_plural}-en-#{city_param}/#{name_param}-#{primary_cat_slug}-#{provider.short_uuid}"

        expect(slug).to eq(expected_pattern),
          "Expected slug '#{expected_pattern}' but got '#{slug}'"
      end
    end
  end

  context "when slug is URL-safe" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "contains only URL-safe characters (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true)

        # Allow the provider to find its primary category
        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        # URL-safe means: lowercase letters, numbers, hyphens, slashes only
        url_safe_pattern = %r{\A[a-z0-9\-/]+\z}
        expect(slug).to match(url_safe_pattern),
          "Expected slug to be URL-safe but got '#{slug}' (contains invalid characters)"

        # Should not contain spaces
        expect(slug).not_to include(" "),
          "Expected slug to not contain spaces but got '#{slug}'"

        # Should not contain uppercase letters
        expect(slug).to eq(slug.downcase),
          "Expected slug to be lowercase but got '#{slug}'"
      end
    end
  end

  context "when slug has the correct structure" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "has exactly one forward slash separating category-city from name-uuid (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true)

        # Allow the provider to find its primary category
        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        # Should have exactly one forward slash
        slash_count = slug.count("/")
        expect(slash_count).to eq(1),
          "Expected exactly 1 forward slash but got #{slash_count} in '#{slug}'"

        # Split by slash and verify both parts
        parts = slug.split("/")
        expect(parts.length).to eq(2),
          "Expected 2 parts when split by '/' but got #{parts.length}"

        # First part should contain category and city
        first_part = parts[0]
        expect(first_part).to include(primary_category.slug.pluralize),
          "Expected first part to contain category plural"
        expect(first_part).to include(provider.city.parameterize),
          "Expected first part to contain city"

        # Second part should contain name, category, and uuid
        second_part = parts[1]
        expect(second_part).to include(provider.name.parameterize),
          "Expected second part to contain name"
        expect(second_part).to include(primary_category.slug),
          "Expected second part to contain category"
        expect(second_part).to include(provider.short_uuid),
          "Expected second part to contain short_uuid"
      end
    end
  end

  context "when slug handles special characters in input" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "parameterizes names and cities correctly (iteration #{iteration + 1})" do
        # Generate names and cities with special characters
        special_names = [
          "José García",
          "María de los Ángeles",
          "Técnico & Plomero",
          "Electricista (Certificado)",
          "Pintor/Decorador"
        ]

        special_cities = [
          "México City",
          "San Luis Potosí",
          "Nuevo León",
          "Quintana Roo"
        ]

        name = special_names.sample
        city = special_cities.sample

        provider = build_stubbed(:provider, name: name, city: city)
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true)

        # Allow the provider to find its primary category
        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        # Slug should be URL-safe despite special input
        url_safe_pattern = %r{\A[a-z0-9\-/]+\z}
        expect(slug).to match(url_safe_pattern),
          "Expected slug to be URL-safe even with special characters in input, but got '#{slug}'"

        # Verify parameterization happened
        expect(slug).to include(name.parameterize),
          "Expected slug to include parameterized name"
        expect(slug).to include(city.parameterize),
          "Expected slug to include parameterized city"
      end
    end
  end
end
