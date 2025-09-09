class AddReviewableToLists < ActiveRecord::Migration[8.0]
  def change
    add_column :lists, :reviewable, :boolean, default: false, null: false
    add_index :lists, :reviewable
  end
end
