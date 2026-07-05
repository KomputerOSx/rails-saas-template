require "test_helper"

class AdminNotificationsTest < ActionDispatch::IntegrationTest
  def sign_in_as_system_admin(user)
    role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    user.grant_role!(role)
    post login_path, params: { email: user.email, password: "password123" }
    assert_redirected_to dashboard_path
  end

  test "non-system-admin cannot reach the admin notifications section" do
    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    assert_difference -> { AuditLog.where(event_type: :authorization_denied).count }, 1 do
      get admin_notifications_path
    end

    assert_redirected_to root_path
  end

  test "system admin can send a notification to specific users" do
    sign_in_as_system_admin(users(:one))

    assert_difference -> { Notification.count }, 1 do
      post admin_notifications_path, params: { notification: { title: "Hi", body: "Body", user_ids: [ users(:two).id ] } }
    end

    notification = Notification.order(:created_at).last
    assert_equal [ users(:two) ], notification.recipients
    assert_equal 1, AuditLog.where(event_type: :notification_created).count
  end

  test "system admin can send a notification to all users, ignoring user_ids" do
    sign_in_as_system_admin(users(:one))

    post admin_notifications_path, params: {
      notification: { title: "Hi", body: "Body", send_to_all: "1", user_ids: [ users(:two).id ] }
    }

    notification = Notification.order(:created_at).last
    assert_equal User.count, notification.recipients.count
  end

  test "system admin can withdraw a notification, audited, and it disappears from recipients' inboxes" do
    sign_in_as_system_admin(users(:one))
    notification = Notification.deliver!(title: "Hi", body: "Body", to: users(:two))

    patch withdraw_admin_notification_path(notification)

    assert notification.reload.withdrawn?
    assert_equal 1, AuditLog.where(event_type: :notification_withdrawn).count
    assert_not_includes users(:two).notification_recipients.inbox.map(&:notification), notification
  end
end
