require "test_helper"

class RegistrationConfirmationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "confirming a new signup provisions a personal organization with the owner role" do
    email = "new-org-user@example.com"

    perform_enqueued_jobs do
      post registration_path, params: {
        user: { email: email, password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52" }
      }
    end
    assert_redirected_to new_confirmation_path

    code = extract_code_from_last_email

    assert_difference [ "User.count", "Organization.count", "Membership.count", "MembershipRole.count" ], 1 do
      post confirmations_path, params: { code: code.chars }
    end
    assert_redirected_to dashboard_path

    user = User.find_by!(email: email)
    assert_equal 1, user.organizations.count
    membership = user.memberships.first
    assert membership.has_role?(Role::APP_OWNER, scope: :app)

    assert AuditLog.exists?(user: user, event_type: :organization_created)
    assert AuditLog.exists?(user: user, event_type: :membership_created)
  end

  test "a failure during organization provisioning leaves no User row behind" do
    email = "atomicity-user@example.com"

    perform_enqueued_jobs do
      post registration_path, params: {
        user: { email: email, password: "Tr8kMvln52", password_confirmation: "Tr8kMvln52" }
      }
    end

    code = extract_code_from_last_email

    original_method = Organization.method(:create_personal_for!)
    Organization.define_singleton_method(:create_personal_for!) { |*| raise ActiveRecord::RecordInvalid.new(Organization.new) }

    begin
      assert_no_difference [ "User.count", "Organization.count" ] do
        post confirmations_path, params: { code: code.chars }
      end
      assert_response :unprocessable_entity
    ensure
      Organization.define_singleton_method(:create_personal_for!, original_method)
    end

    assert_not User.exists?(email: email)
  end

  private

  def extract_code_from_last_email
    body = ActionMailer::Base.deliveries.last.body.encoded
    body[/(\d{6})/, 1]
  end
end
