class CreateVoteSessions < ActiveRecord::Migration[8.0]
  def change
    # One round of voting on a channel: the shortlist that was put up, and the votes cast
    # on it. Kept after it closes so the result can still be read.
    create_table :vote_sessions do |t|
      t.references :list, null: false, foreign_key: true
      t.datetime :closed_at

      t.timestamps
    end

    # An entry on the ballot. Removing one takes its votes with it.
    create_table :vote_options do |t|
      t.references :vote_session, null: false, foreign_key: true
      t.references :entry, null: false, foreign_key: true
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :vote_options, [:vote_session_id, :entry_id], unique: true

    # A phone, identified only by a token in its own cookie -- no account, nothing typed.
    # One vote per device per round, changeable while the round is open.
    create_table :votes do |t|
      t.references :vote_session, null: false, foreign_key: true
      t.references :vote_option, null: false, foreign_key: true
      t.string :voter_token, null: false

      t.timestamps
    end

    add_index :votes, [:vote_session_id, :voter_token], unique: true
  end
end
