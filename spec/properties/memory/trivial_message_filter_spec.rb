# frozen_string_literal: true

# Feature: trato-mvp, Property 8: Trivial messages are never persisted
# **Validates: Requirements 12.1**
#
# For any message whose body is in the trivial set ("ok", "gracias",
# "perfecto", "listo", "entendido", "si", "no", standalone emojis),
# the should_save_message value SHALL always be false.

require "rails_helper"

RSpec.describe MessagePersistenceFilter, "P8: trivial messages never persisted", type: :property do
  TRIVIAL_WORDS = %w[ok gracias perfecto listo entendido si no].freeze

  # Common standalone emojis for testing
  STANDALONE_EMOJIS = %w[👍 😊 🙏 ✅ 👌 😄 🎉 ❤️ 💪 🤝 😁 🙂 👏 🔥 ⭐].freeze

  context "when body is a trivial word" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "returns false for should_save? (iteration #{iteration + 1})" do
        trivial_body = TRIVIAL_WORDS.sample

        # Apply random casing variations
        body = case rand(4)
        when 0 then trivial_body
        when 1 then trivial_body.upcase
        when 2 then trivial_body.capitalize
        else trivial_body
        end

        # Add random whitespace padding
        body = "  #{body}  " if rand(2).zero?

        result = MessagePersistenceFilter.should_save?(body: body, intent: nil)

        expect(result).to be(false),
          "Expected should_save? to be false for trivial body '#{body}' " \
          "but got #{result.inspect} (iteration #{iteration + 1})"
      end
    end
  end

  context "when body is a standalone emoji" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "returns false for should_save? (iteration #{iteration + 1})" do
        emoji = STANDALONE_EMOJIS.sample

        # Optionally combine 1-3 emojis (still standalone emoji message)
        body = case rand(3)
        when 0 then emoji
        when 1 then "#{emoji}#{STANDALONE_EMOJIS.sample}"
        else "#{emoji} #{STANDALONE_EMOJIS.sample} #{STANDALONE_EMOJIS.sample}"
        end

        result = MessagePersistenceFilter.should_save?(body: body, intent: nil)

        expect(result).to be(false),
          "Expected should_save? to be false for emoji body '#{body}' " \
          "but got #{result.inspect} (iteration #{iteration + 1})"
      end
    end
  end

  context "when body is trivial and intent is nil" do
    it "trivial_body? returns true for all trivial words" do
      TRIVIAL_WORDS.each do |word|
        expect(MessagePersistenceFilter.trivial_body?(word)).to be(true),
          "Expected trivial_body? to be true for '#{word}'"
      end
    end

    it "trivial_body? returns true for blank/nil bodies" do
      [ nil, "", "  " ].each do |body|
        expect(MessagePersistenceFilter.trivial_body?(body)).to be(true),
          "Expected trivial_body? to be true for #{body.inspect}"
      end
    end
  end
end
