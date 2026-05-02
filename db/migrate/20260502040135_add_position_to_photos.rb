class AddPositionToPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :photos, :position, :integer, default: 0
  end
end
