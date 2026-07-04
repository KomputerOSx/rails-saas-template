class AuditLog < ApplicationRecord
  belongs_to :user, optional: true

  serialize :metadata, coder: JSON

  enum :event_type, {
    login_success: "login_success",
    login_failure: "login_failure",
    logout: "logout",
    user_registered: "user_registered",
    account_confirmed: "account_confirmed",
    email_change_requested: "email_change_requested",
    email_change_confirmed: "email_change_confirmed",
    email_change_cancelled: "email_change_cancelled",
    password_change: "password_change",
    password_reset_requested: "password_reset_requested",
    password_reset_completed: "password_reset_completed",
    password_reset_failed: "password_reset_failed",
    user_deleted: "user_deleted"
  }

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :security_events, -> { where(event_type: %w[login_failure password_reset_requested password_reset_failed]) }
end
