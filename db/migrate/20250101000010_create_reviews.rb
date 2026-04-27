# frozen_string_literal: true

class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :job, null: false, foreign_key: true, index: false

      t.integer :rating
      t.text :comment
      t.boolean :verified, default: true

      t.timestamps
    end

    # One review per job — unique constraint
    add_index :reviews, :job_id, unique: true
  end
end
