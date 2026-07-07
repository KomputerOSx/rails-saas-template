require "test_helper"

class UserRoleTest < ActiveSupport::TestCase
  test "rejects an app-scoped role" do
    app_role = Role.create!(scope: :app, name: "custom_app_role")

    user_role = UserRole.new(user: users(:one), role: app_role)
    assert_not user_role.valid?
  end

  test "accepts a system-scoped role" do
    system_role = Role.create!(scope: :system, name: "custom_system_role")

    user_role = UserRole.new(user: users(:one), role: system_role)
    assert user_role.valid?
  end

  test "blocks revoking the platform's last system admin" do
    admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN)
    users(:one).grant_role!(admin_role)

    user_role = users(:one).user_roles.find_by(role: admin_role)
    assert_not user_role.destroy
    assert_includes user_role.errors.full_messages, "cannot revoke the last system admin"
    assert UserRole.exists?(user_role.id)
  end

  test "allows revoking a system admin once a second one exists" do
    admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN)
    users(:one).grant_role!(admin_role)
    users(:two).grant_role!(admin_role)

    user_role_one = users(:one).user_roles.find_by(role: admin_role)
    assert user_role_one.destroy
    assert_not UserRole.exists?(user_role_one.id)
  end
end
