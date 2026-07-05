require "test_helper"

class AdminAuthorizationTest < ActionDispatch::IntegrationTest
  test "non-admin is redirected away from the admin namespace and the denial is audited" do
    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    assert_difference -> { AuditLog.where(event_type: :authorization_denied).count }, 1 do
      get admin_root_path
    end

    assert_redirected_to root_path
  end

  test "system_admin can access the admin namespace" do
    role = Role.create!(scope: :system, name: "system_admin", permanent: true)
    users(:one).grant_role!(role)

    post login_path, params: { email: users(:one).email, password: "password123" }
    assert_redirected_to dashboard_path

    get admin_root_path
    assert_response :success
  end

  test "granting and revoking a role via the admin UI is audited" do
    admin_role = Role.create!(scope: :system, name: "system_admin", permanent: true)
    users(:one).grant_role!(admin_role)
    target_role = Role.create!(scope: :app, name: "beta_tester")

    post login_path, params: { email: users(:one).email, password: "password123" }

    assert_difference -> { users(:two).roles.count }, 1 do
      post admin_user_user_role_path(users(:two)), params: { role_id: target_role.id }
    end
    assert_equal 1, AuditLog.where(event_type: :role_granted).count

    assert_difference -> { users(:two).roles.count }, -1 do
      delete admin_user_user_role_path(users(:two), role_id: target_role.id)
    end
    assert_equal 1, AuditLog.where(event_type: :role_revoked).count
  end
end
