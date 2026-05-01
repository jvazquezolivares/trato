# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClientLookupService do
  let(:provider) { instance_double(Provider, id: 1) }
  let(:client) { instance_double(Client, id: 42, name: nil, phone: "5212219876543") }

  before do
    allow(Client).to receive(:find_or_create_by!).and_return(client)
    allow(client).to receive(:name).and_return(nil)
    allow(client).to receive(:update!).and_return(true)
    allow(ProviderClient).to receive(:find_or_create_by!).and_yield(ProviderClient.new).and_return(true)
  end

  describe ".call" do
    context "when client exists with matching phone" do
      before do
        allow(client).to receive(:name).and_return("Mariana López")
      end

      it "finds the existing client by phone" do
        described_class.call(phone: "5212219876543", name: "Mariana", provider: provider)

        expect(Client).to have_received(:find_or_create_by!).with(phone: "5212219876543")
      end

      it "does not update name if already present" do
        described_class.call(phone: "5212219876543", name: "Mariana", provider: provider)

        expect(client).not_to have_received(:update!)
      end
    end

    context "when client exists but name is missing" do
      it "updates the missing name" do
        described_class.call(phone: "5212219876543", name: "Mariana López", provider: provider)

        expect(client).to have_received(:update!).with(hash_including(name: "Mariana López"))
      end
    end

    context "when no name is provided" do
      it "does not attempt to update" do
        described_class.call(phone: "5212219876543", provider: provider)

        expect(client).not_to have_received(:update!)
      end
    end

    context "when provider is given" do
      it "ensures ProviderClient association exists" do
        described_class.call(phone: "5212219876543", provider: provider)

        expect(ProviderClient).to have_received(:find_or_create_by!).with(
          provider: provider,
          client: client
        )
      end
    end

    context "when provider is nil" do
      it "does not create ProviderClient association" do
        described_class.call(phone: "5212219876543")

        expect(ProviderClient).not_to have_received(:find_or_create_by!)
      end
    end

    it "returns the client" do
      result = described_class.call(phone: "5212219876543", provider: provider)

      expect(result).to eq(client)
    end
  end
end
