require "test_helper"

class OrgMembersTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "the sole owner cannot remove their own membership" do
    post login_path, params: { email: @owner.email, password: "password123" }

    membership = @owner.memberships.first

    assert_no_difference "Membership.count" do
      delete org_member_path(membership)
    end
    assert_redirected_to org_members_path
    assert AuditLog.exists?(event_type: :owner_removal_blocked)
  end

  test "removing an owner succeeds once a second owner exists" do
    post login_path, params: { email: @owner.email, password: "password123" }

    owner_role = Role.find_by!(scope: :app, name: Role::APP_OWNER)
    second_membership = @organization.memberships.create!(user: users(:two))
    second_membership.grant_role!(owner_role)

    membership = @owner.memberships.first

    assert_difference "Membership.count", -1 do
      delete org_member_path(membership)
    end
    assert_redirected_to org_members_path
    assert AuditLog.exists?(event_type: :membership_destroyed)
  end

  test "a plain user can view the members list but cannot remove members" do
    user_role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)
    plain_member = @organization.memberships.create!(user: users(:two))
    plain_member.grant_role!(user_role)

    post login_path, params: { email: users(:two).email, password: "password123" }

    get org_members_path
    assert_response :success

    assert_no_difference "Membership.count" do
      delete org_member_path(@owner.memberships.first)
    end
    assert_redirected_to root_path
  end

  test "an admin can invite and remove members but cannot promote/demote" do
    admin_role = Role.find_or_create_by!(scope: :app, name: Role::APP_ADMIN)
    admin_membership = @organization.memberships.create!(user: users(:two))
    admin_membership.grant_role!(admin_role)

    post login_path, params: { email: users(:two).email, password: "password123" }

    assert_difference "OrganizationInvitation.count", 1 do
      post org_invitations_path, params: { email: "invitee@example.com" }
    end

    patch promote_org_member_path(admin_membership)
    assert_redirected_to root_path
  end
end
