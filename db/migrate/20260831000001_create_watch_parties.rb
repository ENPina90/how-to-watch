# frozen_string_literal: true

class CreateWatchParties < ActiveRecord::Migration[8.1]
  def change
    create_table :watch_parties do |t|
      t.references :list, null: false, foreign_key: true
      t.references :host_user, null: false, foreign_key: { to_table: :users }
      t.references :entry, null: false, foreign_key: true
      t.references :subentry, null: true, foreign_key: true

      # How a guest reaches the party: the token is the whole invitation, so it has to be
      # unguessable rather than merely unique.
      t.string :token, null: false

      # The last thing the host's player reported, kept so someone arriving late lands in
      # the right place instead of waiting up to five seconds for the next heartbeat.
      t.string   :player_status, null: false, default: 'paused'
      t.float    :player_progress, null: false, default: 0.0
      t.datetime :state_at

      t.datetime :closed_at
      t.timestamps
    end

    add_index :watch_parties, :token, unique: true
    # One open party per host: the host's player is the clock, and it cannot keep time for
    # two rooms at once. Closed ones stay, so `closed_at` is part of the key.
    add_index :watch_parties, :host_user_id, unique: true, where: 'closed_at IS NULL',
                              name: 'index_watch_parties_on_open_host'

    create_table :watch_party_memberships do |t|
      t.references :watch_party, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :last_seen_at, null: false
      t.timestamps
    end

    add_index :watch_party_memberships, %i[watch_party_id user_id], unique: true,
                                        name: 'index_watch_party_memberships_on_party_and_user'
  end
end
