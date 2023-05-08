class CreateEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :entries do |t|
      t.string :name
      t.string :pic
      t.text :plot
      t.string :genre
      t.integer :rating
      t.string :source
      t.string :year
      t.string :director
      t.string :writer
      t.string :actors
      t.string :media
      t.string :length
      t.references :list, null: false, foreign_key: true
      t.string :note
      t.string :review
      t.boolean :completed
      t.string :category

      t.timestamps
    end
  end
end
