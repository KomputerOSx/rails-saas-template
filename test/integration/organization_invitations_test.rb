require "test_helper"

class OrganizationInvitationsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "an existing confirmed user can accept an invitation after logging in" do
    invitee = users(:two)

    invitation, raw_token = invite_user(invitee.email)

    get invitation_path(raw_token)
    assert_redirected_to login_path
    assert_equal raw_token, session[:pending_invitation_token]

    post login_path, params: { email: invitee.email, password: "password123" }
    assert_redirected_to dashboard_path

    invitation.reload
    assert invitation.accepted_at.present?
    assert invitee.memberships.exists?(organization: @organization)
    assert AuditLog.exists?(event_type: :organization_invitation_accepted, user: invitee)
  end

  test "an existing user with 2FA enabled still resumes the invitation after completing login" do
    invitee = users(:two)
    invitee.enable_totp!(User.generate_totp_secret)

    invitation, raw_token = invite_user(invitee.email)

    get invitation_path(raw_token)
    assert_redirected_to login_path

    post login_path, params: { email: invitee.email, password: "password123" }
    assert_redirected_to two_factor_login_path

    code = ROTP::TOTP.new(invitee.totp_secret).now
    post verify_two_factor_login_path, params: { code: code.chars }
    assert_redirected_to dashboard_path

    assert invitation.reload.accepted_at.present?
    assert invitee.memberships.exists?(organization: @organization)
  end

  test "a brand-new signup joins both their own personal organization and the invited one" do
    email = "brand-new-invitee@example.com"
    invitation, raw_token = invite_user(email)

    get invitation_path(raw_token)
    assert_redirected_to new_registration_path(email: email)

    perform_enqueued_jobs do
      post registration_path, params: {
        user: { email: email, password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52" }
      }
    end

    code = ActionMailer::Base.deliveries.last.body.encoded[/(\d{6})/, 1]
    post confirmations_path, params: { code: code.chars }
    assert_redirected_to dashboard_path

    user = User.find_by!(email: email)
    assert_equal 2, user.organizations.count
    assert user.memberships.exists?(organization: @organization)
    assert invitation.reload.accepted_at.present?
  end

  test "an invalid token shows a generic error instead of raising" do
    get invitation_path("not-a-real-token")
    assert_redirected_to login_path
  end

  private

  def invite_user(email)
    user_role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)
    OrganizationInvitation.generate_for!(organization: @organization, email: email, role: user_role, invited_by: @owner)
  end
end
