class AddPrivateToList < ActiveRecord::Migration[7.0]
  def change
    add_column :lists, :private, :boolean
  end
end
