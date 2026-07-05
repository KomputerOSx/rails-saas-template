require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "has_permission? without an organization only checks system-scope roles" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))
    custom_role = Role.create!(scope: :app, name: "custom_role")
    permission = Permission.create!(key: "app.custom.manage")
    RolePermission.create!(role: custom_role, permission: permission)
    membership.grant_role!(custom_role)

    assert_not users(:one).has_permission?("app.custom.manage")
  end

  test "has_permission? with an organization delegates to that membership" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))
    custom_role = Role.create!(scope: :app, name: "custom_role")
    permission = Permission.create!(key: "app.custom.manage")
    RolePermission.create!(role: custom_role, permission: permission)

    assert_not users(:one).has_permission?("app.custom.manage", organization: organization)

    membership.grant_role!(custom_role)

    assert users(:one).has_permission?("app.custom.manage", organization: organization)
  end

  test "has_permission? with an organization the user isn't a member of returns false" do
    organization = Organization.create!(name: "Acme", slug: "acme")

    assert_not users(:one).has_permission?("app.custom.manage", organization: organization)
  end
end
