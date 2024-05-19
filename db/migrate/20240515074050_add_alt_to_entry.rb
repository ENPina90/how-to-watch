class AddAltToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :alt, :string
  end
end
