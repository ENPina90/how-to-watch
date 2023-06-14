class AddSortToList < ActiveRecord::Migration[7.0]
  def change
    add_column :lists, :sort, :string
  end
end
