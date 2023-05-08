class AddLanguageToEntries < ActiveRecord::Migration[7.0]
  def change
    add_column :entries, :language, :string
  end
end
