# frozen_string_literal: true

class CreateAppointments < ActiveRecord::Migration[8.1]
  def change
    create_table :appointments do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :work_day, null: true, foreign_key: true
      t.text :description
      t.string :address
      t.datetime :scheduled_at
      t.integer :estimated_duration, default: 60
      t.string :status
      t.string :how_client_arrived
      t.text :notes

      t.timestamps
    end

    add_index :appointments, %i[provider_id scheduled_at]
    add_index :appointments, :status
  end
end
