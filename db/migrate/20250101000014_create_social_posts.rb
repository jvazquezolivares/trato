# frozen_string_literal: true

class CreateSocialPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :social_posts do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :photo, null: false, foreign_key: true
      t.text :caption_generated
      t.string :platform
      t.string :status
      t.datetime :published_at
      t.text :error_message

      t.timestamps
    end
  end
end
