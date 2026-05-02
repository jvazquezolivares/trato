# frozen_string_literal: true

# Feature: trato-mvp, Property 4: assistant_whatsapp_link always contains short_uuid and number
# **Validates: Requirements 2.4, 2.5**
#
# For any Provider record with a given short_uuid, the computed method
# assistant_whatsapp_link SHALL always return a URL with a personalized Spanish message
# containing the provider name and short_uuid embedded in the text parameter.
# The short_uuid must be extractable via regex pattern /\b[0-9a-f]{8}\b/i for routing purposes.

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

        # 4. Link must have a text parameter
        expect(link).to include("?text="),
          "Expected link to have text parameter but got '#{link}'"
      end
    end
  end

  context "when short_uuid is embedded in personalized message" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "embeds the short_uuid and provider name in a URL-encoded Spanish message (iteration #{iteration + 1})" do
        provider = build_stubbed(:provider)

        link = provider.assistant_whatsapp_link

        # Decode the URL to check the message
        uri = URI.parse(link)
        params = URI.decode_www_form(uri.query)
        text_param = params.find { |k, _v| k == "text" }&.last

        expect(text_param).not_to be_nil,
          "Expected text parameter in link '#{link}'"

        # The message should contain the short_uuid
        expect(text_param).to include(provider.short_uuid),
          "Expected message to contain short_uuid '#{provider.short_uuid}' but got '#{text_param}'"

        # The message should contain the provider name
        expect(text_param).to include(provider.name),
          "Expected message to contain provider name '#{provider.name}' but got '#{text_param}'"

        # The message should be in Spanish and instructional
        expect(text_param).to match(/Envía este mensaje/i),
          "Expected Spanish instruction in message but got '#{text_param}'"

        # The short_uuid should be extractable via regex
        match = text_param.match(/\b[0-9a-f]{8}\b/i)
        expect(match).not_to be_nil,
          "Expected to extract short_uuid via regex from '#{text_param}'"
        expect(match[0].downcase).to eq(provider.short_uuid),
          "Expected extracted UUID '#{match[0]}' to match provider.short_uuid '#{provider.short_uuid}'"
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

        # 4. The text parameter must be properly URL-encoded
        text_value = params[0][1]
        expect(text_value).not_to be_empty,
          "Expected non-empty text parameter"
      end
    end
  end
end
