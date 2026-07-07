require "test_helper"

class AdminRbacEnforcementTest < ActionDispatch::IntegrationTest
  # config/rbac.yml grants system_user both system.users.manage and
  # system.roles.manage out of the box - these tests exercise what happens when
  # an operator's access is narrowed by revoking one of those permissions.
  setup do
    @system_user_role = Role.find_by!(scope: "system", name: Role::SYSTEM_USER)
    @manage_users_permission = Permission.find_by!(key: "system.users.manage")
    @manage_roles_permission = Permission.find_by!(key: "system.roles.manage")

    @user = users(:one)
    @user.grant_role!(@system_user_role)

    post login_path, params: { email: @user.email, password: "password123" }
  end

  test "a system_operator without system.users.manage cannot reach admin users, but can reach the admin namespace" do
    get admin_root_path
    assert_response :success

    get admin_users_path
    assert_response :success

    @system_user_role.permissions.delete(@manage_users_permission)

    get admin_users_path
    assert_redirected_to root_path

    get admin_root_path
    assert_response :success
  end

  test "revoking system.roles.manage locks a system_operator out of admin roles and permissions" do
    get admin_roles_path
    assert_response :success
    get admin_permissions_path
    assert_response :success

    @system_user_role.permissions.delete(@manage_roles_permission)

    get admin_roles_path
    assert_redirected_to root_path
    get admin_permissions_path
    assert_redirected_to root_path
  end

  test "a user with no system-scoped role at all cannot reach the admin namespace" do
    @user.revoke_role!(@system_user_role)

    get admin_root_path
    assert_redirected_to root_path
  end
end
