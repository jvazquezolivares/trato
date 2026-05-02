class AddReviewsCountToProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :providers, :reviews_count, :integer, default: 0, null: false

    # Backfill existing counts
    reversible do |dir|
      dir.up do
        Provider.find_each do |provider|
          Provider.reset_counters(provider.id, :reviews)
        end
      end
    end
  end
end
