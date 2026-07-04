class AuditLog < ApplicationRecord
  belongs_to :user, optional: true

  serialize :metadata, coder: JSON

  enum :event_type, {
    login_success: "login_success",
    login_failure: "login_failure",
    logout: "logout",
    session_created: "session_created",
    session_destroyed: "session_destroyed",
    account_locked: "account_locked",
    account_unlocked: "account_unlocked",
    two_factor_challenge_sent: "two_factor_challenge_sent",
    two_factor_success: "two_factor_success",
    two_factor_failure: "two_factor_failure",
    totp_enabled: "totp_enabled",
    totp_disabled: "totp_disabled",
    totp_email_fallback_requested: "totp_email_fallback_requested",
    user_registered: "user_registered",
    account_confirmed: "account_confirmed",
    email_change_requested: "email_change_requested",
    email_change_confirmed_old: "email_change_confirmed_old",
    email_change_confirmed_new: "email_change_confirmed_new",
    email_change_completed: "email_change_completed",
    email_change_cancelled: "email_change_cancelled",
    password_change: "password_change",
    password_reset_requested: "password_reset_requested",
    password_reset_link_sent: "password_reset_link_sent",
    password_reset_completed: "password_reset_completed",
    password_reset_failed: "password_reset_failed",
    user_deleted: "user_deleted",
    rate_limit_triggered: "rate_limit_triggered"
  }

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :security_events, -> { where(event_type: %w[login_failure account_locked rate_limit_triggered password_reset_requested password_reset_failed]) }
end
