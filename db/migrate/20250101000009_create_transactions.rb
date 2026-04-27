# frozen_string_literal: true

# CRITICAL: Column is named `transaction_type` (NOT `type`) to avoid Rails STI conflict.
# The Transaction model uses `transaction_type` with values "income" or "expense".
class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :job, null: true, foreign_key: true
      t.references :client, null: true, foreign_key: true
      t.decimal :amount
      t.string :transaction_type
      t.text :description
      t.string :payment_method
      t.datetime :recorded_at
      t.string :assigned_to

      t.timestamps
    end

    add_index :transactions, %i[provider_id recorded_at]
    add_index :transactions, %i[provider_id transaction_type]
  end
end
