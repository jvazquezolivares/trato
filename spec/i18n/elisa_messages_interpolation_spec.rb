# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Elisa I18n Message Interpolation", type: :i18n do
  describe "Provider messages with interpolation" do
    it "greeting message includes provider name" do
      message = I18n.t("elisa.provider.onboarding.greeting", name: "Miguel")

      expect(message).to include("Miguel")
      expect(message).to include("👋")
    end

    it "area_prompt message includes city name" do
      message = I18n.t("elisa.provider.onboarding.area_prompt", city: "Veracruz")

      expect(message).to include("Veracruz")
      expect(message).to match(/zonas.*colonias/i)
    end

    it "completion message includes name and URLs" do
      message = I18n.t(
        "elisa.provider.completion.message",
        name: "Miguel",
        profile_url: "https://trato.com/miguel",
        assistant_link: "https://wa.me/123"
      )

      expect(message).to include("Miguel")
      expect(message).to include("https://trato.com/miguel")
      expect(message).to include("https://wa.me/123")
    end

    it "morning_summary with_tasks_header uses correct pluralization" do
      singular_message = I18n.t(
        "elisa.provider.morning_summary.with_tasks_header",
        count: 1,
        tasks_word: I18n.t("elisa.provider.morning_summary.singular_task")
      )

      plural_message = I18n.t(
        "elisa.provider.morning_summary.with_tasks_header",
        count: 3,
        tasks_word: I18n.t("elisa.provider.morning_summary.plural_tasks")
      )

      expect(singular_message).to include("1")
      expect(singular_message).to include("pendiente")
      expect(plural_message).to include("3")
      expect(plural_message).to include("pendientes")
    end

    it "auto_reply suggestion includes assistant link" do
      message = I18n.t(
        "elisa.provider.auto_reply.suggestion",
        assistant_link: "https://wa.me/123456"
      )

      expect(message).to include("https://wa.me/123456")
      expect(message).to include("Elisa")
    end
  end

  describe "Client messages with interpolation" do
    it "region_detection greeting includes state name" do
      message = I18n.t("elisa.client.region_detection.greeting", state: "Veracruz")

      expect(message).to include("Veracruz")
      expect(message).to include("👋")
    end

    it "region_detection retry_prompt includes state name" do
      message = I18n.t("elisa.client.region_detection.retry_prompt", state: "Puebla")

      expect(message).to include("Puebla")
    end

    it "appointment no_workday includes provider name" do
      message = I18n.t("elisa.client.appointment.no_workday", name: "Miguel")

      expect(message).to include("Miguel")
    end

    it "appointment escalation_confirmed includes provider name" do
      message = I18n.t("elisa.client.appointment.escalation_confirmed", name: "Miguel")

      expect(message).to include("Miguel")
    end

    it "emergency client_alert includes all required fields" do
      message = I18n.t(
        "elisa.client.emergency.client_alert",
        name: "María",
        provider_name: "Miguel",
        phone: "5212211234567"
      )

      expect(message).to include("María")
      expect(message).to include("Miguel")
      expect(message).to include("5212211234567")
      expect(message).to include("🚨")
      expect(message).to include("911")
    end

    it "emergency provider_alert includes all required fields" do
      message = I18n.t(
        "elisa.client.emergency.provider_alert",
        name: "María",
        keyword: "humo",
        phone: "5212219876543"
      )

      expect(message).to include("María")
      expect(message).to include("humo")
      expect(message).to include("5212219876543")
      expect(message).to include("🚨")
      expect(message).to include("URGENTE")
    end

    it "review rating_ack includes rating number" do
      (1..5).each do |rating|
        message = I18n.t("elisa.client.review.rating_ack", rating: rating)

        expect(message).to include(rating.to_s)
        expect(message).to include("⭐")
      end
    end

    it "review comment_request includes provider name" do
      message = I18n.t("elisa.client.review.comment_request", name: "Miguel")

      expect(message).to include("Miguel")
    end
  end

  describe "Message formatting and grammar" do
    it "maintains proper Spanish grammar in greetings" do
      greeting = I18n.t("elisa.provider.onboarding.greeting", name: "Ana")

      # Should use correct article and preposition
      expect(greeting).to match(/Mucho gusto, Ana/)
    end

    it "maintains proper Spanish grammar in region detection" do
      message = I18n.t("elisa.client.region_detection.greeting", state: "Veracruz")

      # Should use "de" before state name
      expect(message).to match(/eres de Veracruz/)
    end

    it "emergency messages use informal 'tú' form appropriately" do
      client_alert = I18n.t(
        "elisa.client.emergency.client_alert",
        name: "María",
        provider_name: "Miguel",
        phone: "5212211234567"
      )

      # Should use informal commands (aléjate, llama) for urgency
      expect(client_alert).to match(/aléjate|llama/i)
    end

    it "maintains emoji consistency across messages" do
      welcome = I18n.t("elisa.provider.onboarding.welcome")
      greeting = I18n.t("elisa.provider.onboarding.greeting", name: "Test")
      client_greeting = I18n.t("elisa.client.region_detection.greeting", state: "Test")

      # All greetings should include wave emoji
      expect(welcome).to include("👋")
      expect(greeting).to include("👋")
      expect(client_greeting).to include("👋")
    end
  end

  describe "Interpolation variables presence" do
    # Rails I18n by default does not raise errors on missing interpolation arguments.
    # These tests verify that messages with interpolation work correctly when variables are provided.

    it "all interpolated messages work with their required variables" do
      # Provider messages
      expect(I18n.t("elisa.provider.onboarding.greeting", name: "Test")).to be_present
      expect(I18n.t("elisa.provider.onboarding.area_prompt", city: "Test")).to be_present
      expect(I18n.t("elisa.provider.completion.message", name: "Test", profile_url: "url", assistant_link: "link")).to be_present

      # Client messages
      expect(I18n.t("elisa.client.region_detection.greeting", state: "Test")).to be_present
      expect(I18n.t("elisa.client.emergency.client_alert", name: "Test", provider_name: "Test", phone: "123")).to be_present
      expect(I18n.t("elisa.client.emergency.provider_alert", name: "Test", keyword: "test", phone: "123")).to be_present
      expect(I18n.t("elisa.client.review.rating_ack", rating: 5)).to be_present
      expect(I18n.t("elisa.client.review.comment_request", name: "Test")).to be_present
    end
  end
end
