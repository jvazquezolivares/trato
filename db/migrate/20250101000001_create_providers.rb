# frozen_string_literal: true

class CreateProviders < ActiveRecord::Migration[8.1]
  def change
    create_table :providers do |t|
      t.string :name
      t.string :phone
      t.string :short_uuid
      t.string :city
      t.text :service_area
      t.decimal :base_price
      t.text :bio
      t.string :slug
      t.string :email
      t.string :facebook_page_url
      t.string :facebook_token
      t.datetime :facebook_token_expires_at
      t.string :instagram_token
      t.boolean :active, default: true
      t.datetime :onboarded_at

      t.timestamps
    end

    add_index :providers, :phone, unique: true
    add_index :providers, :short_uuid, unique: true
    add_index :providers, :slug, unique: true
    add_index :providers, %i[city active]
  end
end
