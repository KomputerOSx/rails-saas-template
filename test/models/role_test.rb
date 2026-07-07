require "test_helper"

class RoleTest < ActiveSupport::TestCase
  test "name must be lowercase snake_case" do
    role = Role.new(scope: :app, name: "Not Valid")
    assert_not role.valid?
    assert_includes role.errors[:name], "is invalid"

    role.name = "valid_name"
    assert role.valid?
  end

  test "name is unique per scope, but the same name can exist in different scopes" do
    Role.create!(scope: :app, name: "operator")

    duplicate = Role.new(scope: :app, name: "operator")
    assert_not duplicate.valid?

    different_scope = Role.new(scope: :system, name: "operator")
    assert different_scope.valid?
  end

  test "a permanent role cannot be renamed" do
    role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }

    role.name = "renamed_admin"

    assert_not role.save
    assert_includes role.errors[:base], "cannot rename a permanent role"
    assert_equal Role::SYSTEM_ADMIN, role.reload.name
  end

  test "a permanent role cannot be destroyed" do
    role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }

    assert_not role.destroy
    assert_includes role.errors[:base], "cannot delete a permanent role"
    assert Role.exists?(role.id)
  end

  test "a non-permanent role can be renamed and destroyed" do
    role = Role.create!(scope: :app, name: "temp_role", permanent: false)

    assert role.update(name: "renamed_role")
    assert role.destroy
  end
end
