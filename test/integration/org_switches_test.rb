require "test_helper"

class OrgSwitchesTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @first_organization = Organization.create_personal_for!(@user)
    @second_organization = Organization.create!(name: "Second Org", slug: "second-org")
    @second_organization.memberships.create!(user: @user)

    post login_path, params: { email: @user.email, password: "password123" }
  end

  test "switching to an organization the user belongs to updates the session" do
    post org_switch_path, params: { organization_id: @second_organization.id }

    assert_redirected_to dashboard_path
    get dashboard_path
    assert_equal @second_organization.id, session[:current_organization_id]
  end

  test "switching to an organization the user does not belong to is rejected" do
    other_organization = Organization.create!(name: "Not Mine", slug: "not-mine")

    post org_switch_path, params: { organization_id: other_organization.id }

    assert_redirected_to dashboard_path
    follow_redirect!
    assert_not_equal other_organization.id, session[:current_organization_id]
  end
end
