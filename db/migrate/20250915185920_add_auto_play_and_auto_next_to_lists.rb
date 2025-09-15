class AddAutoPlayAndAutoNextToLists < ActiveRecord::Migration[8.0]
  def change
    add_column :lists, :auto_play, :boolean, default: true
    add_column :lists, :auto_next, :boolean, default: true
  end
end
