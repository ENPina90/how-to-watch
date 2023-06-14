class AddSettingsToList < ActiveRecord::Migration[7.0]
  def change
    add_column :lists, :settings, :string
  end
end
