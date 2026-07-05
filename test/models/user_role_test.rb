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
end
