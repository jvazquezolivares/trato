# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistants::ReviewSummaryService do
  let(:provider) { instance_double(Provider, id: 1, slug: "electricistas-en-veracruz/miguel-a3f8c2d1") }
  let(:reviews_relation) { double("reviews_relation") }
  let(:client_phone) { "5212219876543" }

  before do
    allow(provider).to receive(:reviews).and_return(reviews_relation)
    allow(reviews_relation).to receive(:where).with(verified: true).and_return(reviews_relation)
    allow(WhatsAppService).to receive(:send_message).and_return(true)
  end

  describe ".stats" do
    context "when provider has verified reviews" do
      before do
        allow(reviews_relation).to receive(:count).and_return(5)
        allow(reviews_relation).to receive(:average).with(:rating).and_return(4.5)
      end

      it "returns average and count" do
        result = described_class.stats(provider: provider)

        expect(result).to eq({ average: "4.5/5", count: 5 })
      end
    end

    context "when provider has no reviews" do
      before do
        allow(reviews_relation).to receive(:count).and_return(0)
      end

      it "returns no rating message" do
        result = described_class.stats(provider: provider)

        expect(result).to eq({ average: "Sin calificación aún", count: 0 })
      end
    end
  end

  describe ".call" do
    context "when provider has reviews" do
      let(:review) { instance_double(Review, rating: 5, comment: "Excelente trabajo") }

      before do
        allow(reviews_relation).to receive(:empty?).and_return(false)
        allow(reviews_relation).to receive(:count).and_return(3)
        allow(reviews_relation).to receive(:average).with(:rating).and_return(4.7)
        allow(reviews_relation).to receive(:order).and_return(reviews_relation)
        allow(reviews_relation).to receive(:limit).with(2).and_return([ review ])
      end

      it "sends review summary to client" do
        described_class.call(provider: provider, to: client_phone)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/4\.7\/5.*3 reseñas verificadas/)
        )
      end

      it "sends profile link after summary" do
        described_class.call(provider: provider, to: client_phone)

        expect(WhatsAppService).to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/Perfil completo/)
        )
      end

      it "skips profile link when send_profile_link is false" do
        described_class.call(provider: provider, to: client_phone, send_profile_link: false)

        expect(WhatsAppService).not_to have_received(:send_message).with(
          to: client_phone,
          message: a_string_matching(/Perfil completo/)
        )
      end
    end

    context "when provider has no reviews" do
      before do
        allow(reviews_relation).to receive(:empty?).and_return(true)
      end

      it "does not send any message" do
        described_class.call(provider: provider, to: client_phone)

        expect(WhatsAppService).not_to have_received(:send_message)
      end
    end
  end
end
