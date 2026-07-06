require "test_helper"

class AdminFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }

    @feature = Feature.create!(key: "widget_beta", name: "Widget Beta", manager_activation_required: true)
    @org_a = Organization.create_personal_for!(users(:two))
  end

  test "system_admin can toggle a feature's global enabled flag" do
    patch admin_feature_path(@feature), params: { feature: { enabled: "1" } }

    assert_redirected_to admin_features_path
    assert @feature.reload.enabled?
    assert AuditLog.exists?(event_type: :feature_updated)
  end

  test "system_admin can grant a feature to organizations" do
    assert_difference "FeatureOrganizationAccess.count", 1 do
      patch admin_feature_path(@feature), params: { feature: { enabled: "1", organization_ids: [ @org_a.id ] } }
    end

    assert @feature.feature_organization_accesses.enabled.exists?(organization: @org_a)
    assert AuditLog.exists?(event_type: :feature_access_granted)
  end

  test "revoking a previously granted organization flips enabled rather than destroying the row" do
    patch admin_feature_path(@feature), params: { feature: { enabled: "1", organization_ids: [ @org_a.id ] } }

    assert_no_difference "FeatureOrganizationAccess.count" do
      patch admin_feature_path(@feature), params: { feature: { enabled: "1", organization_ids: [] } }
    end

    access = @feature.feature_organization_accesses.find_by(organization: @org_a)
    assert access.present?
    assert_not access.enabled?
    assert AuditLog.exists?(event_type: :feature_access_revoked)
  end

  test "a non-admin is denied" do
    plain_user = users(:two)
    post login_path, params: { email: plain_user.email, password: "password123" }

    patch admin_feature_path(@feature), params: { feature: { enabled: "1" } }

    assert_redirected_to root_path
    assert_not @feature.reload.enabled?
  end
end
