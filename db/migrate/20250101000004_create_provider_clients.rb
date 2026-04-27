# frozen_string_literal: true

class CreateProviderClients < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_clients do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.text :notes
      t.datetime :last_contacted_at

      t.timestamps
    end

    add_index :provider_clients, %i[provider_id client_id], unique: true
  end
end
