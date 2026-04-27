# frozen_string_literal: true

class CreateWorkDays < ActiveRecord::Migration[8.1]
  def change
    create_table :work_days do |t|
      t.references :provider, null: false, foreign_key: true
      t.date :date
      t.time :starts_at
      t.time :ends_at
      t.string :status
      t.text :notes

      t.timestamps
    end

    add_index :work_days, %i[provider_id date], unique: true
  end
end
