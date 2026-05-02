# frozen_string_literal: true

# Feature: trato-mvp, Property 4: assistant_whatsapp_link always contains short_uuid and number
# **Validates: Requirements 2.4, 2.5**
#
# For any Provider record with a given short_uuid, the computed method
# assistant_whatsapp_link SHALL always return a URL matching the pattern
# https://wa.me/{TRATO_WHATSAPP_NUMBER}?text={short_uuid}, where short_uuid
# is an 8-character hexadecimal string and TRATO_WHATSAPP_NUMBER is the
# shared WhatsApp Business number from the environment.

require "rails_helper"

RSpec.describe Provider, "P4: assistant_whatsapp_link format", type: :property do
  context "when provider has a valid short_uuid" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "returns a properly formatted WhatsApp link (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)

        link = provider.assistant_whatsapp_link

        # 1. Link must start with https://wa.me/
        expect(link).to match(%r{\Ahttps://wa\.me/}),
          "Expected link to start with 'https://wa.me/' but got '#{link}'"

        # 2. Link must contain the TRATO_WHATSAPP_NUMBER
        whatsapp_number = ENV["TRATO_WHATSAPP_NUMBER"]
        expect(link).to include(whatsapp_number),
          "Expected link to contain TRATO_WHATSAPP_NUMBER '#{whatsapp_number}' but got '#{link}'"

        # 3. Link must contain the provider's short_uuid
        expect(link).to include(provider.short_uuid),
          "Expected link to contain short_uuid '#{provider.short_uuid}' but got '#{link}'"

        # 4. Link must match the full pattern: https://wa.me/{number}?text={uuid}
        expected_pattern = %r{\Ahttps://wa\.me/#{Regexp.escape(whatsapp_number)}\?text=[a-f0-9]{8}\z}
        expect(link).to match(expected_pattern),
          "Expected link to match pattern but got '#{link}'"
      end
    end
  end

  context "when short_uuid is always 8 hex characters" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "extracts and validates the short_uuid from the link (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)

        link = provider.assistant_whatsapp_link

        # Extract the short_uuid from the link (after ?text=)
        match = link.match(%r{\?text=([a-f0-9]{8})\z})
        expect(match).not_to be_nil,
          "Expected to extract short_uuid from link '#{link}'"

        extracted_uuid = match[1]

        # Verify it matches the provider's short_uuid
        expect(extracted_uuid).to eq(provider.short_uuid),
          "Expected extracted UUID '#{extracted_uuid}' to match provider.short_uuid '#{provider.short_uuid}'"

        # Verify it's exactly 8 hex characters
        expect(extracted_uuid).to match(/\A[a-f0-9]{8}\z/),
          "Expected UUID to be 8 hex characters but got '#{extracted_uuid}'"
      end
    end
  end

  context "when TRATO_WHATSAPP_NUMBER changes" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "always uses the current ENV value (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)

        link = provider.assistant_whatsapp_link

        # The link must contain the current ENV value
        current_number = ENV["TRATO_WHATSAPP_NUMBER"]
        expect(link).to include(current_number),
          "Expected link to use current TRATO_WHATSAPP_NUMBER '#{current_number}' but got '#{link}'"
      end
    end
  end

  context "when link is used as a WhatsApp URL" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "is a valid WhatsApp deep link (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)

        link = provider.assistant_whatsapp_link

        # 1. Must be HTTPS (secure)
        expect(link).to start_with("https://"),
          "Expected HTTPS link but got '#{link}'"

        # 2. Must be a valid URI
        expect { URI.parse(link) }.not_to raise_error,
          "Expected valid URI but got '#{link}'"

        # 3. Must have exactly one query parameter (text)
        uri = URI.parse(link)
        params = URI.decode_www_form(uri.query)
        expect(params.length).to eq(1),
          "Expected exactly 1 query parameter but got #{params.length} in '#{link}'"
        expect(params[0][0]).to eq("text"),
          "Expected query parameter 'text' but got '#{params[0][0]}'"
      end
    end
  end
end
