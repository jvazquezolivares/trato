# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::ClientPromptBuilder do
  let(:provider) do
    instance_double(
      Provider,
      id: 1, name: "Miguel García", phone: "5212211234567",
      city: "Veracruz", service_area: "Boca del Río",
      base_price: "$200–400 MXN", bio: "Electricista con experiencia",
      slug: "electricistas-en-veracruz/miguel-a3f8c2d1"
    )
  end

  let(:client) { instance_double(Client, id: 42, name: "Mariana López") }
  let(:conversation) { instance_double(Conversation, id: 1, context: {}, messages: messages_relation) }
  let(:messages_relation) { double("messages_relation") }
  let(:ordered_messages) { double("ordered_messages") }
  let(:from) { "5212219876543" }

  let(:provider_categories_relation) { double("categories_relation") }
  let(:reviews_relation) { double("reviews_relation") }
  let(:work_days_relation) { double("work_days_relation") }
  let(:photos_relation) { double("photos_relation") }

  before do
    allow(provider).to receive(:provider_categories).and_return(provider_categories_relation)
    allow(provider_categories_relation).to receive(:pluck).with(:name).and_return([ "Electricista" ])
    allow(provider_categories_relation).to receive(:pluck).with(:slug).and_return([ "electricista" ])

    allow(provider).to receive(:reviews).and_return(reviews_relation)
    allow(reviews_relation).to receive(:where).with(verified: true).and_return(reviews_relation)
    allow(reviews_relation).to receive(:count).and_return(5)
    allow(reviews_relation).to receive(:average).with(:rating).and_return(4.5)

    allow(provider).to receive(:work_days).and_return(work_days_relation)
    allow(work_days_relation).to receive(:find_by).and_return(nil)

    allow(provider).to receive(:photos).and_return(photos_relation)
    allow(photos_relation).to receive(:where).with(profile_photo: false).and_return(photos_relation)
    allow(photos_relation).to receive(:pluck).with(:category_tags).and_return([ [ "electricista" ] ])

    allow(messages_relation).to receive(:order).and_return(ordered_messages)
    allow(ordered_messages).to receive(:limit).and_return([])
  end

  describe ".call" do
    it "returns a hash with system_prompt and context" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result).to have_key(:system_prompt)
      expect(result).to have_key(:context)
    end

    it "includes provider name in system prompt" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:system_prompt]).to include("Miguel García")
    end

    it "includes Elisa in system prompt" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:system_prompt]).to include("Elisa")
    end

    it "includes provider categories" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:system_prompt]).to include("Electricista")
    end

    it "includes review stats" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:system_prompt]).to match(/4\.5\/5.*5 reseñas/)
    end

    it "includes availability summary" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:system_prompt]).to include("No ha reportado disponibilidad hoy")
    end

    it "includes photo categories" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:system_prompt]).to include("electricista")
    end

    it "includes client name" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:system_prompt]).to include("Mariana López")
    end

    it "includes history in context" do
      result = described_class.call(provider: provider, client: client, conversation: conversation, from: from)

      expect(result[:context]).to have_key("history")
    end
  end

  describe ".search_mode_prompt" do
    it "returns the search mode template" do
      prompt = described_class.search_mode_prompt

      expect(prompt).to include("Elisa")
      expect(prompt).to include("plataforma que conecta clientes con técnicos")
    end
  end
end
