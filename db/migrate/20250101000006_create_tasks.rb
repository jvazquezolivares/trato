# frozen_string_literal: true

class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :work_day, null: true, foreign_key: true
      t.text :description
      t.string :status
      t.string :priority
      t.datetime :snoozed_until
      t.datetime :completed_at

      t.timestamps
    end
  end
end
