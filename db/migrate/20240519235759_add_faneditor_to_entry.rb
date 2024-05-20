class AddFaneditorToEntry < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :faneditor, :string
  end
end
