class AddCurrentToEntries < ActiveRecord::Migration[7.0]
  def change
    add_reference :entries, :current, foreign_key: { to_table: :subentries }
  end
end
