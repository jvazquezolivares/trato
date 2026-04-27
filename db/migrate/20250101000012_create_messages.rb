# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :direction
      t.text :body
      t.string :media_url
      t.string :intent
      t.boolean :processed, default: false

      t.timestamps
    end

    add_index :messages, %i[conversation_id created_at]

    # Partial index for unprocessed messages — enables efficient queue-like queries
    add_index :messages, :processed, where: "processed = false", name: "index_messages_on_unprocessed"
  end
end
