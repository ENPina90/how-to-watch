class AddFranchiseToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :franchise, :string
  end
end
