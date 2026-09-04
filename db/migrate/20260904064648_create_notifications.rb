# frozen_string_literal: true

# Things the app wants to tell one person about.
#
# Built general rather than as a source-expiry table, because expiry warnings are only the
# first kind: a channel being created, somebody subscribing to yours, and whatever else
# follows all want the same row shape and the same dismissal behaviour. `kind` names the
# sort of thing, `subject` points at whatever it is about, and everything specific to one
# kind goes in `data` rather than in a column no other kind would use.
class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true

      t.string :kind, null: false
      t.references :subject, polymorphic: true, null: true
      t.jsonb :data, null: false, default: {}

      # See the unique index below for what this is for.
      t.string :dedupe_key, null: false

      t.datetime :dismissed_at

      t.timestamps
    end

    # Identifies the exact thing being reported, so a scan that runs daily does not stack up
    # a copy per day. For an expiry warning it carries the date being warned about, which
    # means renewing a provider retires the old warning rather than leaving it to be
    # dismissed by hand.
    add_index :notifications, %i[user_id dedupe_key], unique: true

    # The badge and the page both ask the same question: what is still undismissed for this
    # person, newest first.
    add_index :notifications, %i[user_id dismissed_at created_at]
  end
end
