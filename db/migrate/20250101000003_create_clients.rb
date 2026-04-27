# frozen_string_literal: true

class CreateClients < ActiveRecord::Migration[8.1]
  def change
    create_table :clients do |t|
      t.string :name
      t.string :phone
      t.decimal :rating

      t.timestamps
    end

    add_index :clients, :phone, unique: true
  end
end
