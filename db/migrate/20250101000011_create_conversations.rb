# frozen_string_literal: true

class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.string :phone
      t.string :role
      t.references :provider, null: false, foreign_key: true
      t.references :client, null: true, foreign_key: true
      t.string :stage
      t.jsonb :context
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :conversations, :phone, unique: true
    add_index :conversations, %i[provider_id stage]
  end
end
