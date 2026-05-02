# frozen_string_literal: true

require "rails_helper"

RSpec.describe Provider, type: :model do
  describe "#assistant_whatsapp_link" do
    it "returns a properly formatted WhatsApp link" do
      provider = build_stubbed(:provider)

      link = provider.assistant_whatsapp_link

      expect(link).to start_with("https://wa.me/")
      expect(link).to include(ENV["TRATO_WHATSAPP_NUMBER"])
      expect(link).to include(provider.short_uuid)
    end

    it "includes the short_uuid as a query parameter" do
      provider = build_stubbed(:provider)

      link = provider.assistant_whatsapp_link

      expect(link).to match(%r{\?text=#{provider.short_uuid}\z})
    end

    it "is a computed method (not a stored column)" do
      provider = build_stubbed(:provider)

      # Verify the method exists and returns a value
      expect(provider.respond_to?(:assistant_whatsapp_link)).to be(true)

      # Verify it's not a database column
      expect(provider.attributes.keys).not_to include("assistant_whatsapp_link")
    end

    it "always uses the current ENV value" do
      provider = build_stubbed(:provider)

      link = provider.assistant_whatsapp_link

      expect(link).to include(ENV["TRATO_WHATSAPP_NUMBER"])
    end

    context "when TRATO_WHATSAPP_NUMBER changes" do
      it "reflects the new number in the link" do
        provider = build_stubbed(:provider)
        original_link = provider.assistant_whatsapp_link

        # Simulate ENV change
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("TRATO_WHATSAPP_NUMBER").and_return("5215551234567")

        new_link = provider.assistant_whatsapp_link

        expect(new_link).not_to eq(original_link)
        expect(new_link).to include("5215551234567")
      end
    end
  end

  describe "#build_slug" do
    context "when provider has a primary category" do
      it "returns a slug matching the expected format" do
        provider = build_stubbed(:provider, name: "Miguel García", city: "México City")
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true, slug: "fontanero")

        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        expect(slug).to include("fontaneros")  # pluralized
        expect(slug).to include("-en-")
        expect(slug).to include("mexico-city")  # parameterized city
        expect(slug).to include("miguel-garcia")  # parameterized name
        expect(slug).to include("fontanero")  # category slug
        expect(slug).to include(provider.short_uuid)
      end

      it "has exactly one forward slash" do
        provider = build_stubbed(:provider)
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true)

        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        expect(slug.count("/")).to eq(1)
      end

      it "is URL-safe (lowercase, hyphens, slashes only)" do
        provider = build_stubbed(:provider, name: "José García", city: "San Luis Potosí")
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true, slug: "electricista")

        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        expect(slug).to match(%r{\A[a-z0-9\-/]+\z})
        expect(slug).not_to include(" ")
        expect(slug).to eq(slug.downcase)
      end

      it "follows the exact pattern: {cat_plural}-en-{city}/{name}-{cat}-{uuid}" do
        provider = build_stubbed(:provider, name: "Juan", city: "Veracruz", short_uuid: "abc12345")
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true, slug: "plomero")

        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        expected = "plomeros-en-veracruz/juan-plomero-abc12345"
        expect(slug).to eq(expected)
      end
    end

    context "when provider has no primary category" do
      it "returns nil" do
        provider = build_stubbed(:provider)

        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: nil)
        )

        slug = provider.build_slug

        expect(slug).to be_nil
      end
    end

    context "when name or city has special characters" do
      it "parameterizes them correctly" do
        provider = build_stubbed(:provider, name: "Técnico & Plomero", city: "Quintana Roo")
        primary_category = build_stubbed(:provider_category, provider: provider, primary: true, slug: "plomero")

        allow(provider).to receive(:provider_categories).and_return(
          instance_double("AssociationProxy", detect: primary_category)
        )

        slug = provider.build_slug

        expect(slug).to include("tecnico-plomero")
        expect(slug).to include("quintana-roo")
        expect(slug).to match(%r{\A[a-z0-9\-/]+\z})
      end
    end
  end

end
