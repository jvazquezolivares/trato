# frozen_string_literal: true

# Finds or creates a global Client record by phone number.
# Client records are shared across all providers — if two providers
# work with the same person (identified by phone), they share one Client.
# Missing fields are updated whenever any provider provides new information.
#
# Also ensures a ProviderClient association exists for the given provider.
#
# Usage:
#   ClientLookupService.call(
#     phone: "5212219876543",
#     name: "Mariana López",
#     provider: provider
#   )
#   # => Client record (existing or newly created)
class ClientLookupService
  def self.call(phone:, name: nil, provider: nil)
    new(phone: phone, name: name, provider: provider).execute
  end

  def initialize(phone:, name: nil, provider: nil)
    @phone = phone
    @name = name
    @provider = provider
  end

  def execute
    client = find_or_create_client
    update_missing_fields(client)
    ensure_provider_client_association(client) if @provider
    client
  end

  private

  def find_or_create_client
    Client.find_or_create_by!(phone: @phone)
  end

  def update_missing_fields(client)
    updates = {}
    updates[:name] = @name if @name.present? && client.name.blank?

    client.update!(updates) if updates.any?
  end

  def ensure_provider_client_association(client)
    ProviderClient.find_or_create_by!(
      provider: @provider,
      client: client
    ) do |provider_client|
      provider_client.last_contacted_at = Time.current
    end
  end
end
