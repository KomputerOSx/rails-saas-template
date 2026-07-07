require "test_helper"

class BillingLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "inviting is blocked once a Free-tier org's sole seat is taken" do
    post login_path, params: { email: @owner.email, password: "password123" }

    assert_no_difference "OrganizationInvitation.count" do
      post org_invitations_path, params: { email: "invitee@example.com" }
    end
    assert_redirected_to org_settings_path
  end

  test "inviting is blocked via turbo_stream too, with a flash message instead of a redirect" do
    post login_path, params: { email: @owner.email, password: "password123" }

    assert_no_difference "OrganizationInvitation.count" do
      post org_invitations_path, params: { email: "invitee@example.com" }, as: :turbo_stream
    end
    assert_response :success
    assert_match "plan is limited", @response.body
  end

  test "inviting succeeds again once the org is on a plan with open seats" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      assert_difference "OrganizationInvitation.count", 1 do
        post org_invitations_path, params: { email: "invitee@example.com" }
      end
    end
  end

  test "accepting an invitation directly is blocked if the org fell back to Free after the invite was sent" do
    invitee = users(:two)
    role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)

    invitation = nil
    raw_token = nil
    with_active_subscription(@organization, Billing::Plans::STARTER) do
      invitation, raw_token = OrganizationInvitation.generate_for!(organization: @organization, email: invitee.email, role: role, invited_by: @owner)

      # Simulate the subscription lapsing (e.g. cancellation) between invite and accept.
      @organization.payment_processor.subscription.update!(status: "canceled", ends_at: 1.day.ago)
    end

    post login_path, params: { email: invitee.email, password: "password123" }
    assert_redirected_to dashboard_path

    post accept_invitation_path(raw_token)
    assert_redirected_to invitation_path(raw_token)

    assert_not invitation.reload.accepted_at.present?
    assert_not invitee.memberships.exists?(organization: @organization)
  end
end
