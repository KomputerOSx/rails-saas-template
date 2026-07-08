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
    rate_limit_triggered: "rate_limit_triggered",
    role_granted: "role_granted",
    role_revoked: "role_revoked",
    authorization_denied: "authorization_denied",
    organization_created: "organization_created",
    membership_created: "membership_created",
    membership_destroyed: "membership_destroyed",
    organization_invitation_sent: "organization_invitation_sent",
    organization_invitation_accepted: "organization_invitation_accepted",
    organization_invitation_revoked: "organization_invitation_revoked",
    owner_removal_blocked: "owner_removal_blocked",
    organization_updated: "organization_updated",
    notification_created: "notification_created",
    notification_withdrawn: "notification_withdrawn",
    maintenance_mode_enabled: "maintenance_mode_enabled",
    maintenance_mode_disabled: "maintenance_mode_disabled",
    sessions_force_logged_out: "sessions_force_logged_out",
    user_disabled: "user_disabled",
    user_enabled: "user_enabled",
    user_updated: "user_updated",
    role_created: "role_created",
    role_updated: "role_updated",
    role_deleted: "role_deleted",
    permission_created: "permission_created",
    permission_updated: "permission_updated",
    permission_deleted: "permission_deleted",
    feature_updated: "feature_updated",
    feature_access_granted: "feature_access_granted",
    feature_access_revoked: "feature_access_revoked",
    organization_feature_settings_updated: "organization_feature_settings_updated",
    subscription_created: "subscription_created",
    subscription_updated: "subscription_updated",
    subscription_cancelled: "subscription_cancelled",
    subscription_resumed: "subscription_resumed",
    subscription_downgrade_scheduled: "subscription_downgrade_scheduled",
    subscription_downgrade_cancelled: "subscription_downgrade_cancelled",
    payment_method_updated: "payment_method_updated",
    payment_method_removed: "payment_method_removed",
    billing_details_updated: "billing_details_updated",
    promotion_code_applied: "promotion_code_applied",
    promotion_code_removed: "promotion_code_removed"
  }

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :security_events, -> { where(event_type: %w[login_failure account_locked rate_limit_triggered password_reset_requested password_reset_failed authorization_denied owner_removal_blocked]) }
end
