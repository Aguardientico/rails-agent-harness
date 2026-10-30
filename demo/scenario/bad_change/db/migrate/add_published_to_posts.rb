class AddPublishedToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :published, :boolean
  end
end
