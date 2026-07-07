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

ActiveRecord::Schema[8.1].define(version: 2026_07_07_222504) do
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

  create_table "feature_organization_accesses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.integer "feature_id", null: false
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["feature_id", "organization_id"], name: "index_feature_org_accesses_on_feature_and_org", unique: true
    t.index ["feature_id"], name: "index_feature_organization_accesses_on_feature_id"
    t.index ["organization_id"], name: "index_feature_organization_accesses_on_organization_id"
  end

  create_table "features", force: :cascade do |t|
    t.boolean "applies_to_all_organizations", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: false, null: false
    t.string "key", null: false
    t.string "name", null: false
    t.boolean "org_opt_in_required", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_features_on_key", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["provider", "uid"], name: "index_identities_on_provider_and_uid", unique: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "membership_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "granted_by_id"
    t.integer "membership_id", null: false
    t.integer "role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["granted_by_id"], name: "index_membership_roles_on_granted_by_id"
    t.index ["membership_id", "role_id"], name: "index_membership_roles_on_membership_id_and_role_id", unique: true
    t.index ["membership_id"], name: "index_membership_roles_on_membership_id"
    t.index ["role_id"], name: "index_membership_roles_on_role_id"
  end

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "organization_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "index_memberships_on_user_id_and_organization_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "notification_recipients", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dismissed_at"
    t.integer "notification_id", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["notification_id", "user_id"], name: "idx_notification_recipients_unique", unique: true
    t.index ["notification_id"], name: "index_notification_recipients_on_notification_id"
    t.index ["user_id", "dismissed_at", "read_at"], name: "idx_notification_recipients_inbox"
    t.index ["user_id"], name: "index_notification_recipients_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "created_by_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.datetime "withdrawn_at"
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["created_by_id"], name: "index_notifications_on_created_by_id"
    t.index ["withdrawn_at"], name: "index_notifications_on_withdrawn_at"
  end

  create_table "organization_invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.integer "invited_by_id"
    t.integer "organization_id", null: false
    t.datetime "revoked_at"
    t.integer "role_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_organization_invitations_on_invited_by_id"
    t.index ["organization_id", "email"], name: "idx_org_invitations_pending_unique", unique: true, where: "accepted_at IS NULL AND revoked_at IS NULL"
    t.index ["organization_id"], name: "index_organization_invitations_on_organization_id"
    t.index ["role_id"], name: "index_organization_invitations_on_role_id"
    t.index ["token_digest"], name: "index_organization_invitations_on_token_digest", unique: true
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "features"
    t.string "name", null: false
    t.datetime "over_member_limit_at"
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_organizations_on_slug", unique: true
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

  create_table "pay_charges", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "amount_refunded"
    t.integer "application_fee_amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "customer_id", null: false
    t.json "data"
    t.json "metadata"
    t.json "object"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.bigint "subscription_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.datetime "deleted_at", precision: nil
    t.json "object"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.json "data"
    t.boolean "default"
    t.string "payment_method_type"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "current_period_end", precision: nil
    t.datetime "current_period_start", precision: nil
    t.bigint "customer_id", null: false
    t.json "data"
    t.datetime "ends_at", precision: nil
    t.json "metadata"
    t.boolean "metered"
    t.string "name", null: false
    t.json "object"
    t.string "pause_behavior"
    t.datetime "pause_resumes_at", precision: nil
    t.datetime "pause_starts_at", precision: nil
    t.string "payment_method_id"
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.string "stripe_account"
    t.datetime "trial_ends_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "event"
    t.string "event_type"
    t.string "processor"
    t.datetime "updated_at", null: false
  end

  create_table "permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_permissions_on_key", unique: true
  end

  create_table "role_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "permission_id", null: false
    t.integer "role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.boolean "permanent", default: false, null: false
    t.string "scope", default: "app", null: false
    t.datetime "updated_at", null: false
    t.index ["scope", "name"], name: "index_roles_on_scope_and_name", unique: true
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

  create_table "user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "granted_by_id"
    t.integer "role_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["granted_by_id"], name: "index_user_roles_on_granted_by_id"
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "account_deletion_code_digest"
    t.datetime "account_deletion_code_sent_at"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
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
    t.datetime "onboarding_completed_at"
    t.string "onboarding_step"
    t.string "password_digest", default: "", null: false
    t.datetime "totp_enabled_at"
    t.integer "totp_last_used_at"
    t.string "totp_secret"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["disabled_at"], name: "index_users_on_disabled_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["locked_until"], name: "index_users_on_locked_until"
  end

  add_foreign_key "audit_logs", "users"
  add_foreign_key "feature_organization_accesses", "features"
  add_foreign_key "feature_organization_accesses", "organizations"
  add_foreign_key "identities", "users"
  add_foreign_key "membership_roles", "memberships"
  add_foreign_key "membership_roles", "roles"
  add_foreign_key "membership_roles", "users", column: "granted_by_id"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "notification_recipients", "notifications"
  add_foreign_key "notification_recipients", "users"
  add_foreign_key "notifications", "users", column: "created_by_id"
  add_foreign_key "organization_invitations", "organizations"
  add_foreign_key "organization_invitations", "roles"
  add_foreign_key "organization_invitations", "users", column: "invited_by_id"
  add_foreign_key "password_histories", "users"
  add_foreign_key "password_reset_tokens", "users"
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "sessions", "users"
  add_foreign_key "two_factor_challenges", "users"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_roles", "users", column: "granted_by_id"
end
