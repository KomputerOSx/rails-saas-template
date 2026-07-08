require "test_helper"

class AdminOrganizationGrandfathersTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }
  end

  test "system_admin can grandfather an organization" do
    organization = Organization.create_personal_for!(users(:two))

    post admin_organization_grandfather_path(organization)

    assert organization.reload.grandfathered?
    assert AuditLog.exists?(event_type: :organization_grandfathered, resource_type: "Organization", resource_id: organization.id)
  end

  test "system_admin can un-grandfather an organization" do
    organization = Organization.create_personal_for!(users(:two))
    organization.grandfather!

    delete admin_organization_grandfather_path(organization)

    assert_not organization.reload.grandfathered?
    assert AuditLog.exists?(event_type: :organization_ungrandfathered, resource_type: "Organization", resource_id: organization.id)
  end

  test "a non-system user cannot grandfather an organization" do
    member = users(:two)
    organization = Organization.create_personal_for!(member)
    post login_path, params: { email: member.email, password: "password123" }

    post admin_organization_grandfather_path(organization)

    assert_not organization.reload.grandfathered?
  end
end
