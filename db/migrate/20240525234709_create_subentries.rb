class CreateSubentries < ActiveRecord::Migration[7.0]
  def change
    create_table :subentries do |t|
      t.references :entry, null: false, foreign_key: true
      t.string :name
      t.string :pic
      t.string :plot
      t.string :imdb
      t.string :season
      t.string :episode

      t.timestamps
    end
  end
end
