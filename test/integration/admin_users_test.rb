require "test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }
  end

  test "index lists users and supports filtering by email" do
    get admin_users_path, params: { q: users(:two).email }
    assert_response :success
  end

  test "show renders a user's memberships and grantable roles" do
    get admin_user_path(users(:two))
    assert_response :success
  end

  test "update changes a user's name and audits it" do
    patch admin_user_path(users(:two)), params: { user: { first_name: "Ada", last_name: "Lovelace" } }

    assert_redirected_to admin_user_path(users(:two))
    assert_equal "Ada", users(:two).reload.first_name
    assert AuditLog.exists?(event_type: :user_updated)
  end

  test "update rerenders on a validation failure" do
    patch admin_user_path(users(:two)), params: { user: { email: "not-an-email" } }

    assert_response :unprocessable_entity
    assert_not_equal "not-an-email", users(:two).reload.email
  end

  test "disable locks a user out and destroys their sessions" do
    other_session = users(:two).sessions.create!

    patch disable_admin_user_path(users(:two))

    assert_redirected_to admin_user_path(users(:two))
    assert users(:two).reload.disabled?
    assert_not Session.exists?(other_session.id)
    assert AuditLog.exists?(event_type: :user_disabled)
  end

  test "enable lifts a disable" do
    users(:two).disable!

    patch enable_admin_user_path(users(:two))

    assert_redirected_to admin_user_path(users(:two))
    assert_not users(:two).reload.disabled?
    assert AuditLog.exists?(event_type: :user_enabled)
  end

  test "send_reset_link emails a password reset link and audits it" do
    assert_enqueued_emails 1 do
      post send_reset_link_admin_user_path(users(:two))
    end

    assert_redirected_to admin_user_path(users(:two))
    assert PasswordResetToken.exists?(user: users(:two))
    assert AuditLog.exists?(event_type: :password_reset_link_sent)
  end
end
