class AddPlaybackPreferencesToUsers < ActiveRecord::Migration[8.0]
  # A member's own answer to Auto Play and Auto Next, overriding whatever each channel
  # says. Nullable with no default, because three states are needed and only two of them
  # are booleans: null is "I have not said", which defers to the channel and is what
  # everybody had before there was a preference to set. A `false` default would silently
  # turn both off for every existing member.
  def change
    add_column :users, :auto_play, :boolean
    add_column :users, :auto_next, :boolean
  end
end
