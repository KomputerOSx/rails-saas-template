require "test_helper"

class AdminRolesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }
  end

  test "system_admin can create a role with permissions" do
    permission = Permission.find_or_create_by!(key: "app.widgets.manage")

    assert_difference "Role.count", 1 do
      post admin_roles_path, params: {
        role: { name: "widget_manager", scope: "app", description: "Manages widgets", permission_ids: [ permission.id ] }
      }
    end

    role = Role.find_by!(name: "widget_manager", scope: "app")
    assert_redirected_to admin_role_path(role)
    assert_equal [ permission ], role.permissions
    assert AuditLog.exists?(event_type: :role_created)
  end

  test "system_admin can edit a role's description and permissions" do
    role = Role.create!(name: "widget_viewer", scope: "app")
    permission = Permission.find_or_create_by!(key: "app.widgets.view")

    patch admin_role_path(role), params: {
      role: { description: "Views widgets", permission_ids: [ permission.id ] }
    }

    assert_redirected_to admin_role_path(role)
    role.reload
    assert_equal "Views widgets", role.description
    assert_equal [ permission ], role.permissions
    assert AuditLog.exists?(event_type: :role_updated)
  end

  test "renaming a permanent role is rejected" do
    system_admin_role = Role.find_by!(scope: :system, name: Role::SYSTEM_ADMIN)

    patch admin_role_path(system_admin_role), params: { role: { name: "renamed" } }

    assert_response :unprocessable_entity
    assert_equal Role::SYSTEM_ADMIN, system_admin_role.reload.name
  end

  test "system_admin can delete a non-permanent role" do
    role = Role.create!(name: "throwaway", scope: "app")

    assert_difference "Role.count", -1 do
      delete admin_role_path(role)
    end
    assert_redirected_to admin_roles_path
    assert AuditLog.exists?(event_type: :role_deleted)
  end

  test "deleting a permanent role is rejected" do
    owner_role = Role.find_by!(scope: :app, name: Role::APP_OWNER)

    assert_no_difference "Role.count" do
      delete admin_role_path(owner_role)
    end
    assert_redirected_to admin_role_path(owner_role)
  end
end
