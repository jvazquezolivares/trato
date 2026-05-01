# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::ProviderSearchService do
  let(:client_phone) { "5212219876543" }

  let(:search_response) do
    {
      "message" => "¿Qué tipo de servicio necesitas?",
      "action" => "none",
      "action_data" => {},
      "new_stage" => "searching",
      "updated_context" => {},
      "should_save_message" => false,
      "intent" => nil
    }
  end

  before do
    allow(ClaudeService).to receive(:call).and_return(search_response)
    allow(WhatsAppService).to receive(:send_message).and_return(true)
    allow(REDIS).to receive(:get).with("search_state:#{client_phone}").and_return(nil)
    allow(REDIS).to receive(:setex).and_return("OK")
  end

  describe ".call" do
    it "calls ClaudeService with search mode prompt" do
      described_class.call(from: client_phone, body: "Busco fontanero")

      expect(ClaudeService).to have_received(:call).with(
        hash_including(
          model: :haiku,
          system_prompt: a_string_matching(/plataforma que conecta clientes/),
          user_message: "Busco fontanero"
        )
      )
    end

    it "sends reply to client" do
      described_class.call(from: client_phone, body: "Busco fontanero")

      expect(WhatsAppService).to have_received(:send_message).with(
        to: client_phone,
        message: search_response["message"]
      )
    end

    it "saves search context in Redis" do
      described_class.call(from: client_phone, body: "Busco fontanero")

      expect(REDIS).to have_received(:setex).with(
        "search_state:#{client_phone}",
        86_400,
        anything
      )
    end

    context "when search finds a single provider" do
      let(:found_provider) do
        instance_double(Provider, id: 2, name: "Carlos Ruiz", city: "Veracruz")
      end

      let(:found_categories) { double("categories") }
      let(:search_scope) { double("search_scope") }

      let(:search_response) do
        {
          "message" => "Encontré uno.",
          "action" => "search_provider",
          "action_data" => { "category" => "fontanero", "city" => "veracruz" },
          "new_stage" => "searching",
          "updated_context" => {},
          "should_save_message" => false,
          "intent" => nil
        }
      end

      before do
        allow(Provider).to receive(:where).with(active: true).and_return(search_scope)
        allow(search_scope).to receive(:where).and_return(search_scope)
        allow(search_scope).to receive(:joins).and_return(search_scope)
        allow(search_scope).to receive(:distinct).and_return(search_scope)
        allow(search_scope).to receive(:limit).with(5).and_return([found_provider])
        allow(search_scope).to receive(:one?).and_return(true)
        allow(search_scope).to receive(:first).and_return(found_provider)
        allow(found_provider).to receive(:provider_categories).and_return(found_categories)
        allow(found_categories).to receive(:pluck).with(:name).and_return(["Fontanero"])
        allow(REDIS).to receive(:del).and_return(1)
      end

      it "transitions to provider conversation" do
        described_class.call(from: client_phone, body: "Fontanero en Veracruz")

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/Elisa.*asistente de Carlos Ruiz/)
        )
      end

      it "cleans up Redis search state" do
        described_class.call(from: client_phone, body: "Fontanero en Veracruz")

        expect(REDIS).to have_received(:del).with("search_state:#{client_phone}")
      end
    end
  end
end
