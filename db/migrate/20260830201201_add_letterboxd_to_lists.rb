class AddLetterboxdToLists < ActiveRecord::Migration[8.0]
  def change
    # Marks the channel built from a member's Letterboxd diary. A flag rather than
    # matching on the name, because disabling the feature has to find and delete exactly
    # that channel, and the member is free to rename it.
    add_column :lists, :letterboxd, :boolean, default: false, null: false

    add_index :lists, %i[user_id letterboxd], where: 'letterboxd'
  end
end
