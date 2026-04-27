# frozen_string_literal: true

class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.references :provider, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.references :appointment, null: true, foreign_key: true
      t.text :description
      t.decimal :amount
      t.decimal :paid_amount, default: 0
      t.string :status
      t.string :payment_method
      t.date :service_date
      t.datetime :review_requested_at
      t.boolean :review_sent, default: false

      t.timestamps
    end

    add_index :jobs, %i[provider_id status]
    add_index :jobs, %i[provider_id service_date]
  end
end
