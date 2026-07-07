require "test_helper"

class OrgOrganizationsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "an owner can rename the organization" do
    post login_path, params: { email: @owner.email, password: "password123" }

    patch org_organization_path, params: { organization: { name: "New Name" } }

    assert_redirected_to org_settings_path
    assert_equal "New Name", @organization.reload.name
    assert AuditLog.exists?(event_type: :organization_updated)
  end

  test "update rerenders settings on a validation failure" do
    post login_path, params: { email: @owner.email, password: "password123" }

    patch org_organization_path, params: { organization: { name: "" } }

    assert_response :unprocessable_entity
    assert_not_equal "", @organization.reload.name
  end

  test "a plain member without app.organization.manage cannot rename the organization" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    patch org_organization_path, params: { organization: { name: "Hijacked Name" } }

    assert_redirected_to root_path
    assert_not_equal "Hijacked Name", @organization.reload.name
  end
end
