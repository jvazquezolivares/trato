class ChangeBasePriceToStringInProviders < ActiveRecord::Migration[8.1]
  def up
    change_column :providers, :base_price, :string
  end

  def down
    change_column :providers, :base_price, :decimal
  end
end
