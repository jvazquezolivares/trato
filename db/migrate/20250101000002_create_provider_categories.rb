# frozen_string_literal: true

class CreateProviderCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_categories do |t|
      t.references :provider, null: false, foreign_key: true
      t.string :name
      t.string :slug
      t.boolean :primary, default: false

      t.timestamps
    end

    add_index :provider_categories, %i[provider_id slug], unique: true
    add_index :provider_categories, %i[provider_id primary]
  end
end
