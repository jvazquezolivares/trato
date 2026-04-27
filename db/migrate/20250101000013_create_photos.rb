# frozen_string_literal: true

class CreatePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :photos do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :job, null: true, foreign_key: true
      t.string :url
      t.text :caption
      t.boolean :profile_photo, default: false
      t.jsonb :category_tags

      t.timestamps
    end
  end
end
