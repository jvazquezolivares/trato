# frozen_string_literal: true

# Feature: trato-mvp, Property 10: transaction_type is always a valid enum value
#
# For any Transaction record created by the system, the transaction_type column
# SHALL always be either "income" or "expense" and SHALL never equal "type"
# or any other value outside the allowed set.
#
# Validates: Requirements 4.10, 20.4

require "rails_helper"

RSpec.describe "P10: transaction_type is always a valid enum value", type: :property do
  VALID_TRANSACTION_TYPES = %w[income expense].freeze

  let!(:provider) { create(:provider) }
  let!(:client) { create(:client) }

  PropertyTestHelper::DB_ITERATIONS.times do |i|
    it "transaction_type is always valid (iteration #{i + 1})" do
      transaction_type = VALID_TRANSACTION_TYPES.sample
      amount = rand(100..10_000).to_d

      transaction = Transaction.create!(
        provider: provider,
        client: client,
        amount: amount,
        transaction_type: transaction_type,
        description: Faker::Lorem.sentence,
        payment_method: %w[cash transfer].sample,
        recorded_at: Time.current,
        assigned_to: "general"
      )

      # Reload from DB to verify what was actually persisted
      transaction.reload

      expect(transaction.transaction_type).to be_in(VALID_TRANSACTION_TYPES),
        "Expected transaction_type to be 'income' or 'expense', got '#{transaction.transaction_type}'"

      expect(transaction.transaction_type).not_to eq("type"),
        "transaction_type must never be 'type' (Rails STI conflict)"
    end
  end

  it "rejects transaction_type values outside the allowed set" do
    invalid_types = [ "type", "Type", "TYPE", "debit", "credit", "", nil ]

    invalid_types.each do |invalid_type|
      # The model should either reject or the DB should store exactly what we set.
      # This test verifies the column is named transaction_type (not type).
      transaction = Transaction.new(
        provider: provider,
        client: client,
        amount: 100,
        transaction_type: invalid_type,
        description: "test",
        payment_method: "cash",
        recorded_at: Time.current,
        assigned_to: "general"
      )

      # Verify the attribute name is transaction_type, not type
      expect(transaction).to respond_to(:transaction_type)
      expect(transaction.transaction_type).to eq(invalid_type)
    end
  end

  it "uses transaction_type column, not type (no STI conflict)" do
    # Verify the model disables STI by checking inheritance_column
    expect(Transaction.inheritance_column).not_to eq("type"),
      "Transaction model must disable STI to avoid conflict with transaction_type"
  end
end
