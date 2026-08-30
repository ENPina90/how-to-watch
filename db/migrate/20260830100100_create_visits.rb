class CreateVisits < ActiveRecord::Migration[8.0]
  def change
    # One row per browser per day, not per request: the dashboard wants "how many people
    # came" and "how many pages did they open", and a row per request would grow without
    # bound to answer the same two questions. page_views counts the requests that rolled
    # into this row.
    create_table :visits do |t|
      # A random token in the visitor's own cookie. Not an identity -- it is how two
      # requests are known to be the same browser, and it is all this table knows about
      # anyone who is not signed in.
      t.string :visitor_token, null: false
      t.date :visited_on, null: false
      t.integer :page_views, null: false, default: 0
      # Set when the visit is signed in, so the dashboard can tell members from strangers.
      t.references :user, foreign_key: true, null: true

      t.timestamps
    end

    # The upsert target: one row per browser per day.
    add_index :visits, [:visitor_token, :visited_on], unique: true
    # Every dashboard query is "the last N days".
    add_index :visits, :visited_on
  end
end
