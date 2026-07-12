require "test_helper"

class OrgMembersTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

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
    assert_redirected_to org_settings_path
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
    assert_redirected_to org_settings_path
    assert AuditLog.exists?(event_type: :membership_destroyed)
  end

  test "a plain user can view the members list but cannot remove members" do
    user_role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)
    plain_member = @organization.memberships.create!(user: users(:two))
    plain_member.grant_role!(user_role)

    post login_path, params: { email: users(:two).email, password: "password123" }

    get org_settings_path
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

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      assert_difference "OrganizationInvitation.count", 1 do
        post org_invitations_path, params: { email: "invitee@example.com" }
      end
    end

    patch promote_org_member_path(admin_membership)
    assert_redirected_to root_path
  end

  test "an owner can promote another member to co-owner with valid confirmation" do
    post login_path, params: { email: @owner.email, password: "password123" }

    plain_member = @organization.memberships.create!(user: users(:two))
    plain_member.grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    code = nil
    assert_enqueued_emails 1 do
      post send_promotion_code_org_member_path(plain_member)
      assert_response :success
    end
    perform_enqueued_jobs
    code = ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]

    patch promote_to_owner_org_member_path(plain_member), params: { typed_confirmation: users(:two).email, code: code.chars }

    assert_redirected_to org_settings_path
    assert plain_member.reload.has_role?(Role::APP_OWNER, scope: :app)
    assert AuditLog.exists?(event_type: :owner_promoted)
  end

  test "promote_to_owner rejects a mismatched typed email" do
    post login_path, params: { email: @owner.email, password: "password123" }

    plain_member = @organization.memberships.create!(user: users(:two))
    plain_member.grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    perform_enqueued_jobs { post send_promotion_code_org_member_path(plain_member) }
    code = ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]

    patch promote_to_owner_org_member_path(plain_member), params: { typed_confirmation: "wrong@example.com", code: code.chars }

    assert_redirected_to org_settings_path
    assert_not plain_member.reload.has_role?(Role::APP_OWNER, scope: :app)
  end

  test "promote_to_owner rejects an invalid confirmation code" do
    post login_path, params: { email: @owner.email, password: "password123" }

    plain_member = @organization.memberships.create!(user: users(:two))
    plain_member.grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    patch promote_to_owner_org_member_path(plain_member), params: { typed_confirmation: users(:two).email, code: "000000".chars }

    assert_redirected_to org_settings_path
    assert_not plain_member.reload.has_role?(Role::APP_OWNER, scope: :app)
  end

  test "an admin cannot promote a member to owner" do
    admin_role = Role.find_or_create_by!(scope: :app, name: Role::APP_ADMIN)
    admin_membership = @organization.memberships.create!(user: users(:two))
    admin_membership.grant_role!(admin_role)

    third_user = User.create!(email: "third@example.com", password: "Xk92!vTqZmR7", confirmed_at: Time.current)
    plain_member = @organization.memberships.create!(user: third_user)
    plain_member.grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: users(:two).email, password: "password123" }

    patch promote_to_owner_org_member_path(plain_member), params: { typed_confirmation: third_user.email, code: "000000".chars }
    assert_redirected_to root_path
    assert_not plain_member.reload.has_role?(Role::APP_OWNER, scope: :app)
  end
end
