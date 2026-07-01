class CreateSources < ActiveRecord::Migration[8.0]
  def change
    create_table :sources do |t|
      t.string  :name, null: false
      t.string  :slug, null: false
      t.string  :kind, null: false, default: "imdb" # "imdb" | "direct"
      t.jsonb   :templates, null: false, default: {} # per media type, e.g. { "movie" => "...", "default" => "..." }
      t.string  :autoplay_param # query param name for autoplay, e.g. "autoplay"; nil = provider ignores autoplay
      t.boolean :active, null: false, default: true
      t.integer :position

      t.timestamps
    end

    add_index :sources, :slug, unique: true
  end
end
