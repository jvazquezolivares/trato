class CreateOnboardingDeclines < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_declines do |t|
      t.string :phone, null: false
      t.string :reason, null: false
      t.jsonb :context

      t.timestamps
    end

    add_index :onboarding_declines, :phone
    add_index :onboarding_declines, :created_at
  end
end
