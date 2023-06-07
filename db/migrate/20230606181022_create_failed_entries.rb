class CreateFailedEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :failed_entries do |t|
      t.string :name
      t.string :alt
      t.string :year

      t.timestamps
    end
  end
end
