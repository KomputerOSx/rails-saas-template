require "test_helper"

class OrgFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)

    @feature = Feature.create!(key: "widget_beta", name: "Widget Beta", manager_activation_required: true)
    @feature.feature_organization_accesses.create!(organization: @organization, enabled: true)
  end

  test "an owner can opt in to a tier-1+tier-2-enabled feature" do
    @feature.update!(enabled: true)
    post login_path, params: { email: @owner.email, password: "password123" }

    patch org_features_path, params: { features: { @feature.key => { enabled: "1" } } }

    assert_redirected_to org_features_path
    assert @organization.reload.feature_enabled?(@feature.key)
    assert AuditLog.exists?(event_type: :organization_feature_settings_updated)
  end

  test "a member without app.organization.manage is denied" do
    user_role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER)
    plain_member = @organization.memberships.create!(user: users(:two))
    plain_member.grant_role!(user_role)

    post login_path, params: { email: users(:two).email, password: "password123" }

    patch org_features_path, params: { features: { @feature.key => { enabled: "1" } } }

    assert_redirected_to root_path
  end

  test "toggling a feature not granted at tier 2 is silently ignored" do
    ungranted = Feature.create!(key: "not_granted", name: "Not Granted", enabled: true, manager_activation_required: true)
    post login_path, params: { email: @owner.email, password: "password123" }

    patch org_features_path, params: { features: { ungranted.key => { enabled: "1" } } }

    assert_redirected_to org_features_path
    assert_equal({}, @organization.reload.feature_settings(ungranted.key))
  end

  test "a feature that does not require org opt-in reads as enabled from tiers 1+2 alone" do
    @feature.update!(enabled: true, manager_activation_required: false)

    assert @organization.reload.feature_enabled?(@feature.key)
  end
end
