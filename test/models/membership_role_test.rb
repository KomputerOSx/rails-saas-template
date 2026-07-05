require "test_helper"

class MembershipRoleTest < ActiveSupport::TestCase
  test "rejects a system-scoped role" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))
    system_role = Role.create!(scope: :system, name: "custom_system_role")

    membership_role = MembershipRole.new(membership: membership, role: system_role)
    assert_not membership_role.valid?
  end

  test "blocks removing the organization's last owner" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))
    owner_role = Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER)
    membership.grant_role!(owner_role)

    membership_role = membership.membership_roles.find_by(role: owner_role)
    assert_not membership_role.destroy
    assert_includes membership_role.errors.full_messages, "cannot remove the organization's last owner"
    assert MembershipRole.exists?(membership_role.id)
  end

  test "allows removing an owner once a second owner exists" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership_one = organization.memberships.create!(user: users(:one))
    membership_two = organization.memberships.create!(user: users(:two))
    owner_role = Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER)

    membership_one.grant_role!(owner_role)
    membership_two.grant_role!(owner_role)

    membership_role_one = membership_one.membership_roles.find_by(role: owner_role)
    assert membership_role_one.destroy
    assert_not MembershipRole.exists?(membership_role_one.id)
  end

  test "destroying the membership itself is also blocked when it's the sole owner" do
    organization = Organization.create!(name: "Acme", slug: "acme")
    membership = organization.memberships.create!(user: users(:one))
    owner_role = Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER)
    membership.grant_role!(owner_role)

    assert_not membership.destroy
    assert Membership.exists?(membership.id)
  end
end
