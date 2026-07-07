require "test_helper"

class RbacRegistryTest < ActiveSupport::TestCase
  test "sync! is idempotent - running it twice doesn't duplicate or error" do
    assert_nothing_raised do
      RbacRegistry.sync!
      RbacRegistry.sync!
    end

    admin_role = Role.find_by!(scope: :system, name: Role::SYSTEM_ADMIN)
    assert_equal 1, RolePermission.where(role: admin_role, permission: Permission.find_by!(key: "system.users.manage")).count
  end

  test "sync! only attaches baseline permissions the first time a role is created" do
    user_role = Role.find_by!(scope: :app, name: Role::APP_USER)
    permission = Permission.find_or_create_by!(key: "app.custom.manage")
    RolePermission.find_or_create_by!(role: user_role, permission: permission)

    RbacRegistry.sync!

    # sync! never touches an already-existing role's permission set, so a manually
    # attached permission survives being re-synced.
    assert_includes user_role.reload.permissions, permission
  end

  test "sync! recreates a deleted non-permanent role with its baseline permissions" do
    user_role = Role.find_by!(scope: :app, name: Role::APP_USER)
    user_role.destroy!
    assert_not Role.exists?(scope: :app, name: Role::APP_USER)

    RbacRegistry.sync!

    recreated = Role.find_by(scope: :app, name: Role::APP_USER)
    assert recreated.present?
    assert_equal [], recreated.permissions.map(&:key)
  end

  test "sync! creates any permission listed in the config that doesn't exist yet" do
    Permission.find_by(key: "system.audit_logs.view")&.destroy

    RbacRegistry.sync!

    assert Permission.exists?(key: "system.audit_logs.view")
  end
end
