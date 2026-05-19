class AddYearsExperienceToProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :providers, :years_experience, :integer
  end
end
