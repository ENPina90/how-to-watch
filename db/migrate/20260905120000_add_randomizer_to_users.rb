class AddRandomizerToUsers < ActiveRecord::Migration[8.0]
  # How far into an entry a member is willing to be dropped, in minutes. Zero -- the
  # default, and what everybody has until they say otherwise -- means start at the
  # beginning, which is what the app has always done.
  #
  # Float rather than integer because the useful values are small: half a minute is a
  # meaningful difference when the whole point is landing somewhere already underway.
  def change
    add_column :users, :randomizer, :float, default: 0.0, null: false
  end
end
