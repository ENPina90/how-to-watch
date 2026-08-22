# Playback URLs are built from Source templates (see Entry#embed_url). Verified before
# writing this: `rails sources:audit` reported 0 of 3463 production entries relying on
# these columns, and nothing in app/ reads them any more.
class DropLegacySourceColumns < ActiveRecord::Migration[8.0]
  def up
    remove_column :entries, :source
    remove_column :entries, :source_two
    remove_column :entries, :preferred_source
    remove_column :lists, :preferred_source
    remove_column :subentries, :source
  end

  # Recreates the columns but not their contents -- the URLs they held are gone. Anything
  # relying on them would need re-deriving from the provider templates.
  def down
    add_column :entries, :source, :string
    add_column :entries, :source_two, :string
    add_column :entries, :preferred_source, :integer
    add_column :lists, :preferred_source, :integer, default: 1
    add_column :subentries, :source, :string
  end
end
