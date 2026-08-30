# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_30_200650) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "access_mode", default: "secure", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "entries", force: :cascade do |t|
    t.string "actors"
    t.string "alt"
    t.string "category"
    t.boolean "completed"
    t.datetime "created_at", null: false
    t.integer "current_episode"
    t.bigint "current_id"
    t.integer "current_season"
    t.string "director"
    t.integer "episode"
    t.string "faneditor"
    t.string "franchise"
    t.string "genre"
    t.string "imdb"
    t.string "language"
    t.integer "length"
    t.float "letterboxd_score"
    t.bigint "list_id", null: false
    t.string "media"
    t.string "name"
    t.string "note"
    t.string "pic"
    t.text "plot"
    t.integer "position"
    t.bigint "provider_id"
    t.float "rating"
    t.string "review"
    t.integer "season"
    t.string "series"
    t.string "series_imdb"
    t.string "source_key"
    t.boolean "stream"
    t.string "tmdb"
    t.string "trailer"
    t.datetime "updated_at", null: false
    t.string "writer"
    t.integer "year"
    t.index ["current_id"], name: "index_entries_on_current_id"
    t.index ["imdb"], name: "index_entries_on_imdb"
    t.index ["list_id", "position"], name: "index_entries_on_list_id_and_position"
    t.index ["list_id"], name: "index_entries_on_list_id"
    t.index ["media"], name: "index_entries_on_media"
    t.index ["provider_id"], name: "index_entries_on_provider_id"
  end

  create_table "failed_entries", force: :cascade do |t|
    t.string "alt"
    t.datetime "created_at", null: false
    t.string "error"
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "year"
  end

  create_table "list_relationships", force: :cascade do |t|
    t.bigint "child_list_id", null: false
    t.datetime "created_at", null: false
    t.bigint "parent_list_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["child_list_id"], name: "idx_list_rel_child"
    t.index ["parent_list_id", "child_list_id"], name: "idx_list_rel_parent_child", unique: true
    t.index ["parent_list_id", "position"], name: "idx_list_rel_parent_position"
  end

  create_table "lists", force: :cascade do |t|
    t.boolean "auto_next", default: true
    t.boolean "auto_play", default: true
    t.datetime "created_at", null: false
    t.integer "current"
    t.boolean "default", default: false, null: false
    t.text "description"
    t.datetime "last_watched_at"
    t.boolean "mobile", default: false, null: false
    t.string "name"
    t.boolean "ordered"
    t.bigint "parent_list_id"
    t.integer "position"
    t.boolean "private"
    t.bigint "provider_id"
    t.boolean "reviewable", default: false, null: false
    t.string "settings"
    t.string "sort"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["default"], name: "index_lists_on_default"
    t.index ["parent_list_id", "position"], name: "index_lists_on_parent_list_id_and_position"
    t.index ["parent_list_id"], name: "index_lists_on_parent_list_id"
    t.index ["provider_id"], name: "index_lists_on_provider_id"
    t.index ["reviewable"], name: "index_lists_on_reviewable"
    t.index ["user_id", "private"], name: "index_lists_on_user_id_and_private"
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "sources", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "autoplay_param"
    t.datetime "created_at", null: false
    t.string "kind", default: "imdb", null: false
    t.string "name", null: false
    t.integer "position"
    t.string "slug", null: false
    t.jsonb "templates", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_sources_on_slug", unique: true
  end

  create_table "subentries", force: :cascade do |t|
    t.boolean "completed"
    t.datetime "created_at", null: false
    t.bigint "entry_id", null: false
    t.integer "episode"
    t.string "imdb"
    t.integer "length"
    t.string "name"
    t.string "pic"
    t.string "plot"
    t.string "rating"
    t.integer "season"
    t.datetime "updated_at", null: false
    t.integer "year"
    t.index ["entry_id", "season", "episode"], name: "index_subentries_on_entry_id_and_season_and_episode"
    t.index ["entry_id"], name: "index_subentries_on_entry_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "list_id", null: false
    t.datetime "subscribed_at", default: -> { "CURRENT_TIMESTAMP" }
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["list_id"], name: "idx_subscriptions_list"
    t.index ["subscribed_at"], name: "idx_subscriptions_subscribed_at"
    t.index ["user_id", "list_id"], name: "idx_subscriptions_user_list", unique: true
    t.index ["user_id"], name: "idx_subscriptions_user"
  end

  create_table "user_entries", force: :cascade do |t|
    t.text "comment"
    t.boolean "completed", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "entry_id", null: false
    t.datetime "last_watched_at"
    t.integer "review"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["entry_id"], name: "idx_user_entries_entry"
    t.index ["user_id", "completed"], name: "idx_user_entries_user_completed"
    t.index ["user_id", "completed_at"], name: "idx_user_entries_user_completed_at"
    t.index ["user_id", "entry_id"], name: "idx_user_entries_user_entry", unique: true
    t.index ["user_id", "review"], name: "idx_user_entries_user_review"
    t.index ["user_id"], name: "idx_user_entries_user"
  end

  create_table "user_entry_positions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_subentry_id"
    t.bigint "entry_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["current_subentry_id"], name: "index_user_entry_positions_on_current_subentry_id"
    t.index ["entry_id"], name: "index_user_entry_positions_on_entry_id"
    t.index ["user_id", "entry_id"], name: "index_user_entry_positions_on_user_id_and_entry_id", unique: true
    t.index ["user_id"], name: "index_user_entry_positions_on_user_id"
  end

  create_table "user_list_positions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_position", default: 1
    t.bigint "list_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["list_id"], name: "index_user_list_positions_on_list_id"
    t.index ["user_id", "list_id"], name: "index_user_list_positions_on_user_id_and_list_id", unique: true
    t.index ["user_id"], name: "index_user_list_positions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "dark_mode", default: true, null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.text "letterboxd_access_token"
    t.boolean "letterboxd_enabled", default: false, null: false
    t.text "letterboxd_refresh_token"
    t.datetime "letterboxd_token_expires_at"
    t.string "letterboxd_user_id"
    t.string "letterboxd_username"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["admin"], name: "index_users_on_admin"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["letterboxd_enabled"], name: "index_users_on_letterboxd_enabled", where: "letterboxd_enabled"
    t.index ["letterboxd_user_id"], name: "index_users_on_letterboxd_user_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "visits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "page_views", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.date "visited_on", null: false
    t.string "visitor_token", null: false
    t.index ["user_id"], name: "index_visits_on_user_id"
    t.index ["visited_on"], name: "index_visits_on_visited_on"
    t.index ["visitor_token", "visited_on"], name: "index_visits_on_visitor_token_and_visited_on", unique: true
  end

  create_table "vote_options", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entry_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "vote_session_id", null: false
    t.index ["entry_id"], name: "index_vote_options_on_entry_id"
    t.index ["vote_session_id", "entry_id"], name: "index_vote_options_on_vote_session_id_and_entry_id", unique: true
    t.index ["vote_session_id"], name: "index_vote_options_on_vote_session_id"
  end

  create_table "vote_sessions", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.bigint "list_id", null: false
    t.datetime "updated_at", null: false
    t.index ["list_id"], name: "index_vote_sessions_on_list_id"
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "vote_option_id", null: false
    t.bigint "vote_session_id", null: false
    t.string "voter_token", null: false
    t.index ["vote_option_id"], name: "index_votes_on_vote_option_id"
    t.index ["vote_session_id", "voter_token"], name: "index_votes_on_vote_session_id_and_voter_token", unique: true
    t.index ["vote_session_id"], name: "index_votes_on_vote_session_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "entries", "lists"
  add_foreign_key "entries", "sources", column: "provider_id"
  add_foreign_key "entries", "subentries", column: "current_id"
  add_foreign_key "list_relationships", "lists", column: "child_list_id"
  add_foreign_key "list_relationships", "lists", column: "parent_list_id"
  add_foreign_key "lists", "lists", column: "parent_list_id"
  add_foreign_key "lists", "sources", column: "provider_id"
  add_foreign_key "lists", "users"
  add_foreign_key "subentries", "entries"
  add_foreign_key "subscriptions", "lists"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "user_entries", "entries"
  add_foreign_key "user_entries", "users"
  add_foreign_key "user_entry_positions", "entries"
  add_foreign_key "user_entry_positions", "subentries", column: "current_subentry_id"
  add_foreign_key "user_entry_positions", "users"
  add_foreign_key "user_list_positions", "lists"
  add_foreign_key "user_list_positions", "users"
  add_foreign_key "visits", "users"
  add_foreign_key "vote_options", "entries"
  add_foreign_key "vote_options", "vote_sessions"
  add_foreign_key "vote_sessions", "lists"
  add_foreign_key "votes", "vote_options"
  add_foreign_key "votes", "vote_sessions"
end
