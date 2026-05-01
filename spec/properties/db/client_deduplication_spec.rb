# frozen_string_literal: true

# Feature: trato-mvp, Property 6: Client deduplication is idempotent
#
# For any phone number, calling the find-or-create Client lookup any number
# of times SHALL always return the same Client record (same id), and any
# missing fields (e.g. name) SHALL be updated on the existing record rather
# than creating a duplicate.
#
# Validates: Requirements 4.4, 4.5

require "rails_helper"

RSpec.describe "P6: Client deduplication is idempotent", type: :property do
  let!(:provider) { create(:provider) }

  PropertyTestHelper::DB_ITERATIONS.times do |i|
    it "returns the same client id for repeated lookups (iteration #{i + 1})" do
      phone = "521#{rand(1_000_000_000..9_999_999_999)}"

      # First call — creates the client
      client_first = ClientLookupService.call(phone: phone, provider: provider)

      # Subsequent calls — should return the same record
      client_second = ClientLookupService.call(phone: phone, provider: provider)
      client_third = ClientLookupService.call(phone: phone, provider: provider)

      expect(client_first.id).to eq(client_second.id),
        "Second lookup returned different id: #{client_second.id} vs #{client_first.id}"
      expect(client_first.id).to eq(client_third.id),
        "Third lookup returned different id: #{client_third.id} vs #{client_first.id}"

      # Verify only one Client record exists for this phone
      expect(Client.where(phone: phone).count).to eq(1),
        "Expected exactly 1 Client with phone #{phone}, found #{Client.where(phone: phone).count}"
    end
  end

  PropertyTestHelper::DB_ITERATIONS.times do |i|
    it "updates missing fields on existing record (iteration #{i + 1})" do
      phone = "521#{rand(1_000_000_000..9_999_999_999)}"
      name = Faker::Name.name

      # First call — create without name
      client_without_name = ClientLookupService.call(phone: phone, provider: provider)
      expect(client_without_name.name).to be_nil

      # Second call — provide name
      client_with_name = ClientLookupService.call(phone: phone, name: name, provider: provider)

      # Same record, now with name filled in
      expect(client_with_name.id).to eq(client_without_name.id)
      expect(client_with_name.reload.name).to eq(name)

      # Third call with a different name — should NOT overwrite existing name
      different_name = Faker::Name.name
      client_again = ClientLookupService.call(phone: phone, name: different_name, provider: provider)

      expect(client_again.id).to eq(client_without_name.id)
      expect(client_again.reload.name).to eq(name),
        "Existing name should not be overwritten. Expected '#{name}', got '#{client_again.name}'"
    end
  end

  it "creates ProviderClient association only once per provider-client pair" do
    phone = "521#{rand(1_000_000_000..9_999_999_999)}"

    3.times { ClientLookupService.call(phone: phone, provider: provider) }

    client = Client.find_by(phone: phone)
    expect(ProviderClient.where(provider: provider, client: client).count).to eq(1)
  end
end
