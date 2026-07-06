require "test_helper"

class AdminPermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }
  end

  test "system_admin can create, edit, and delete a permission" do
    assert_difference "Permission.count", 1 do
      post admin_permissions_path, params: { permission: { key: "app.widgets.manage", description: "Manage widgets" } }
    end

    permission = Permission.find_by!(key: "app.widgets.manage")
    assert_redirected_to admin_permission_path(permission)
    assert AuditLog.exists?(event_type: :permission_created)

    patch admin_permission_path(permission), params: { permission: { description: "Updated description" } }
    assert_redirected_to admin_permission_path(permission)
    assert_equal "Updated description", permission.reload.description
    assert AuditLog.exists?(event_type: :permission_updated)

    assert_difference "Permission.count", -1 do
      delete admin_permission_path(permission)
    end
    assert_redirected_to admin_permissions_path
    assert AuditLog.exists?(event_type: :permission_deleted)
  end

  test "an invalid key is rejected" do
    assert_no_difference "Permission.count" do
      post admin_permissions_path, params: { permission: { key: "NotValid" } }
    end
    assert_response :unprocessable_entity
  end

  test "deleting a permission removes it from roles that had it" do
    role = Role.create!(name: "widget_manager", scope: "app")
    permission = Permission.create!(key: "app.widgets.manage")
    role.permissions << permission

    delete admin_permission_path(permission)

    assert_equal [], role.reload.permissions
  end
end
