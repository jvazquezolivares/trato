# frozen_string_literal: true

# Feature: trato-mvp, Property 9: Critical intents are always persisted
# **Validates: Requirements 12.2**
#
# For any message with an intent in the critical set (job_registered,
# payment_recorded, appointment_confirmed, appointment_cancelled,
# complaint_received, client_first_contact, provider_unavailable,
# expense_registered), the should_save_message value SHALL always be true.

require "rails_helper"

RSpec.describe MessagePersistenceFilter, "P9: critical intents always persisted", type: :property do
  CRITICAL_INTENTS = %w[
    job_registered payment_recorded appointment_confirmed
    appointment_cancelled complaint_received client_first_contact
    provider_unavailable expense_registered
  ].freeze

  context "when intent is critical" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "returns true for should_save? regardless of body (iteration #{iteration + 1})" do
        intent = CRITICAL_INTENTS.sample

        # Generate a random body — could be trivial, could be anything
        body = [
          "ok", "gracias", "perfecto", "listo", "si", "no",
          "👍", "😊", Faker::Lorem.sentence,
          SecureRandom.hex(8), "", nil
        ].sample

        result = MessagePersistenceFilter.should_save?(body: body, intent: intent)

        expect(result).to be(true),
          "Expected should_save? to be true for critical intent '#{intent}' " \
          "with body #{body.inspect} but got #{result.inspect} (iteration #{iteration + 1})"
      end
    end
  end

  context "when intent is critical with varied casing" do
    PropertyTestHelper::MEMORY_ITERATIONS.times do |iteration|
      it "handles case-insensitive intent matching (iteration #{iteration + 1})" do
        intent = CRITICAL_INTENTS.sample

        # Apply random casing
        cased_intent = case rand(3)
                       when 0 then intent.upcase
                       when 1 then intent.capitalize
                       else intent
                       end

        result = MessagePersistenceFilter.critical_intent?(cased_intent)

        expect(result).to be(true),
          "Expected critical_intent? to be true for '#{cased_intent}' " \
          "(iteration #{iteration + 1})"
      end
    end
  end

  context "critical intent takes precedence over trivial body" do
    it "returns true even when body is trivial" do
      CRITICAL_INTENTS.each do |intent|
        %w[ok gracias perfecto listo entendido si no].each do |trivial_body|
          result = MessagePersistenceFilter.should_save?(body: trivial_body, intent: intent)

          expect(result).to be(true),
            "Expected should_save? to be true for critical intent '#{intent}' " \
            "with trivial body '#{trivial_body}'"
        end
      end
    end
  end
end
