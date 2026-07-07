require "test_helper"

class AdminFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:one)
    system_admin_role = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) { |r| r.permanent = true }
    @admin.grant_role!(system_admin_role)

    post login_path, params: { email: @admin.email, password: "password123" }

    @feature = Feature.create!(key: "widget_beta", name: "Widget Beta", org_opt_in_required: true)
    @org_a = Organization.create_personal_for!(users(:two))
  end

  test "system_admin can toggle a feature's global enabled flag via the inline table toggle" do
    patch admin_feature_path(@feature), params: { feature: { enabled: "1" } }

    assert_redirected_to admin_features_path
    assert @feature.reload.enabled?
    assert AuditLog.exists?(event_type: :feature_updated)
  end

  test "system_admin can grant a feature to organizations via the org-selector dialog" do
    assert_difference "FeatureOrganizationAccess.count", 1 do
      patch admin_feature_path(@feature), params: { feature: { organization_ids: [ @org_a.id ] } }
    end

    assert @feature.feature_organization_accesses.enabled.exists?(organization: @org_a)
    assert AuditLog.exists?(event_type: :feature_access_granted)
  end

  test "revoking a previously granted organization flips enabled rather than destroying the row" do
    patch admin_feature_path(@feature), params: { feature: { organization_ids: [ @org_a.id ] } }

    assert_no_difference "FeatureOrganizationAccess.count" do
      patch admin_feature_path(@feature), params: { feature: { organization_ids: [] } }
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

  test "toggling enabled via its inline form does not change any existing organization access" do
    @feature.feature_organization_accesses.create!(organization: @org_a, enabled: true)

    patch admin_feature_path(@feature), params: { feature: { enabled: "1" } }

    access = @feature.feature_organization_accesses.find_by(organization: @org_a)
    assert access.enabled?
  end

  test "toggling org_opt_in_required via its inline form does not change any existing organization access" do
    @feature.feature_organization_accesses.create!(organization: @org_a, enabled: true)

    patch admin_feature_path(@feature), params: { feature: { org_opt_in_required: "0" } }

    access = @feature.feature_organization_accesses.find_by(organization: @org_a)
    assert access.enabled?
  end

  test "applies_to_all_organizations makes the feature available to an organization created afterward, with zero access rows" do
    @feature.update!(enabled: true, applies_to_all_organizations: true)

    new_org = Organization.create_personal_for!(User.create!(email: "later@example.com", password: "Xk92!vTqZmR7", confirmed_at: Time.current))

    assert_equal 0, @feature.feature_organization_accesses.where(organization: new_org).count
    assert @feature.available_to_organization?(new_org)
  end

  test "applies_to_all_organizations skips syncing organization access and preserves prior grants" do
    @feature.feature_organization_accesses.create!(organization: @org_a, enabled: true)

    assert_no_difference "FeatureOrganizationAccess.count" do
      patch admin_feature_path(@feature), params: { feature: { applies_to_all_organizations: "1", organization_ids: [] } }
    end

    access = @feature.feature_organization_accesses.find_by(organization: @org_a)
    assert access.enabled?, "expected the prior grant to survive turning applies_to_all_organizations on"
  end
end
