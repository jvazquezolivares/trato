class AddDeclineReasonToProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :providers, :decline_reason, :string
  end
end
