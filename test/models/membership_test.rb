require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  test "a user can only have one membership per organization" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))

    duplicate = organization.memberships.build(user: users(:one))
    assert_not duplicate.valid?
    assert membership.persisted?
  end

  test "has_role? and has_permission? reflect granted membership roles" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))
    custom_role = Role.create!(scope: :app, name: "custom_role")
    permission = Permission.create!(key: "app.custom.manage")
    RolePermission.create!(role: custom_role, permission: permission)

    assert_not membership.has_role?("custom_role", scope: :app)
    assert_not membership.has_permission?("app.custom.manage")

    membership.grant_role!(custom_role)

    assert membership.has_role?("custom_role", scope: :app)
    assert membership.has_permission?("app.custom.manage")
  end

  test "revoke_role! removes the grant" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))
    custom_role = Role.create!(scope: :app, name: "custom_role")

    membership.grant_role!(custom_role)
    assert membership.has_role?("custom_role", scope: :app)

    membership.revoke_role!(custom_role)
    assert_not membership.has_role?("custom_role", scope: :app)
  end
end
