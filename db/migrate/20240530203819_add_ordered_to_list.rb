class AddOrderedToList < ActiveRecord::Migration[7.0]
  def change
    add_column :lists, :ordered, :boolean
  end
end
