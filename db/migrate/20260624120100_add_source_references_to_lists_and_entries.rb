class AddSourceReferencesToListsAndEntries < ActiveRecord::Migration[8.0]
  def change
    # New FK-based provider selection -> `provider_id` (belongs_to :provider, class_name "Source").
    # Named `provider` rather than `preferred_source` to avoid clobbering the legacy integer
    # `preferred_source` column, which is intentionally LEFT IN PLACE for revert safety
    # (along with the `source`/`source_two` string columns).
    add_reference :lists,   :provider, foreign_key: { to_table: :sources }, null: true
    add_reference :entries, :provider, foreign_key: { to_table: :sources }, null: true

    # Opaque per-entry token for direct-link providers (Drive file id, mega key#fragment,
    # youtube id, or a full URL for the `custom` catch-all). Null for imdb-keyed entries.
    add_column :entries, :source_key, :string
  end
end
