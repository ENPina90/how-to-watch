class RenamePostionToPositionInEntries < ActiveRecord::Migration[7.0]
  def change
    rename_column :entries, :postion, :position
  end
end
