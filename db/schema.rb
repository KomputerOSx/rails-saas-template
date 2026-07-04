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

ActiveRecord::Schema[8.1].define(version: 2026_07_04_030000) do
  create_table "audit_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.string "ip_address"
    t.text "metadata"
    t.bigint "resource_id"
    t.string "resource_type"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id"
    t.index ["created_at"], name: "index_audit_logs_on_created_at"
    t.index ["event_type"], name: "index_audit_logs_on_event_type"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource"
    t.index ["user_id", "event_type"], name: "index_audit_logs_on_user_id_and_event_type"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "password_histories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_password_histories_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_password_histories_on_user_id"
  end

  create_table "password_reset_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "password_digest_snapshot", null: false
    t.string "request_ip"
    t.text "request_user_agent"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_password_reset_tokens_on_token_digest", unique: true
    t.index ["user_id", "expires_at", "used_at"], name: "idx_on_user_id_expires_at_used_at_c8aabddc42"
    t.index ["user_id"], name: "index_password_reset_tokens_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "last_seen_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["expires_at"], name: "index_sessions_on_expires_at"
    t.index ["last_seen_at"], name: "index_sessions_on_last_seen_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "two_factor_challenges", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.string "challenge_id", null: false
    t.string "code_digest"
    t.datetime "created_at", null: false
    t.string "delivery_method", default: "email", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.string "redirect_after"
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["challenge_id"], name: "index_two_factor_challenges_on_challenge_id", unique: true
    t.index ["delivery_method"], name: "index_two_factor_challenges_on_delivery_method"
    t.index ["user_id"], name: "index_two_factor_challenges_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "confirmation_attempts", default: 0, null: false
    t.string "confirmation_code_digest"
    t.datetime "confirmation_sent_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "email_change_attempts", default: 0, null: false
    t.string "email_change_new_code_digest"
    t.datetime "email_change_new_confirmed_at"
    t.string "email_change_old_code_digest"
    t.datetime "email_change_old_confirmed_at"
    t.datetime "email_change_requested_at"
    t.integer "failed_login_attempts", default: 0, null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.datetime "locked_until"
    t.string "password_digest", default: "", null: false
    t.string "role", default: "user", null: false
    t.datetime "totp_enabled_at"
    t.integer "totp_last_used_at"
    t.string "totp_secret"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["locked_until"], name: "index_users_on_locked_until"
    t.index ["role"], name: "index_users_on_role"
  end

  add_foreign_key "audit_logs", "users"
  add_foreign_key "password_histories", "users"
  add_foreign_key "password_reset_tokens", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "two_factor_challenges", "users"
end
