class AddSeriesToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :series, :string
  end
end
