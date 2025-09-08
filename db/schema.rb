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

ActiveRecord::Schema[8.0].define(version: 2025_09_07_232406) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "entries", force: :cascade do |t|
    t.string "name"
    t.string "pic"
    t.text "plot"
    t.string "genre"
    t.string "source"
    t.string "director"
    t.string "writer"
    t.string "actors"
    t.string "media"
    t.bigint "list_id", null: false
    t.string "note"
    t.string "review"
    t.boolean "completed"
    t.string "category"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "imdb"
    t.string "language"
    t.integer "length"
    t.float "rating"
    t.integer "year"
    t.boolean "stream"
    t.string "franchise"
    t.string "alt"
    t.integer "position"
    t.integer "season"
    t.integer "episode"
    t.string "faneditor"
    t.string "series"
    t.integer "current_season"
    t.integer "current_episode"
    t.bigint "current_id"
    t.string "tmdb"
    t.string "trailer"
    t.string "series_imdb"
    t.index ["current_id"], name: "index_entries_on_current_id"
    t.index ["list_id"], name: "index_entries_on_list_id"
  end

  create_table "failed_entries", force: :cascade do |t|
    t.string "name"
    t.string "alt"
    t.string "year"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "error"
  end

  create_table "follows", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "list_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["list_id"], name: "index_follows_on_list_id"
    t.index ["user_id"], name: "index_follows_on_user_id"
  end

  create_table "list_relationships", force: :cascade do |t|
    t.bigint "parent_list_id", null: false
    t.bigint "child_list_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["child_list_id"], name: "idx_list_rel_child"
    t.index ["parent_list_id", "child_list_id"], name: "idx_list_rel_parent_child", unique: true
    t.index ["parent_list_id", "position"], name: "idx_list_rel_parent_position"
  end

  create_table "list_user_entries", force: :cascade do |t|
    t.bigint "list_id", null: false
    t.bigint "user_id", null: false
    t.bigint "current_entry_id"
    t.integer "history", default: [], array: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["current_entry_id"], name: "index_list_user_entries_on_current_entry_id"
    t.index ["list_id"], name: "index_list_user_entries_on_list_id"
    t.index ["user_id"], name: "index_list_user_entries_on_user_id"
  end

  create_table "lists", force: :cascade do |t|
    t.string "name"
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "settings"
    t.string "sort"
    t.integer "current"
    t.boolean "ordered"
    t.boolean "private"
    t.datetime "last_watched_at"
    t.bigint "parent_list_id"
    t.integer "position"
    t.index ["parent_list_id", "position"], name: "index_lists_on_parent_list_id_and_position"
    t.index ["parent_list_id"], name: "index_lists_on_parent_list_id"
    t.index ["user_id"], name: "index_lists_on_user_id"
  end

  create_table "subentries", force: :cascade do |t|
    t.bigint "entry_id", null: false
    t.string "name"
    t.string "pic"
    t.string "plot"
    t.string "imdb"
    t.string "season"
    t.string "episode"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "rating"
    t.integer "length"
    t.boolean "completed"
    t.string "source"
    t.integer "year"
    t.index ["entry_id"], name: "index_subentries_on_entry_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "entries", "lists"
  add_foreign_key "entries", "subentries", column: "current_id"
  add_foreign_key "follows", "lists"
  add_foreign_key "follows", "users"
  add_foreign_key "list_relationships", "lists", column: "child_list_id"
  add_foreign_key "list_relationships", "lists", column: "parent_list_id"
  add_foreign_key "list_user_entries", "entries", column: "current_entry_id"
  add_foreign_key "list_user_entries", "lists"
  add_foreign_key "list_user_entries", "users"
  add_foreign_key "lists", "lists", column: "parent_list_id"
  add_foreign_key "lists", "users"
  add_foreign_key "subentries", "entries"
end
