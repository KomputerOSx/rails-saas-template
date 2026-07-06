require "test_helper"

class FeatureToggleableTest < ActiveSupport::TestCase
  setup do
    @organization = Organization.create!(name: "Acme", slug: "acme-#{SecureRandom.hex(4)}")
    @feature = Feature.create!(key: "widget_beta", name: "Widget Beta", manager_activation_required: true)
  end

  test "all three gates true means the feature is enabled" do
    @feature.update!(enabled: true)
    @feature.feature_organization_accesses.create!(organization: @organization, enabled: true)
    @organization.update_feature!(:widget_beta, enabled: true)

    assert @organization.feature_enabled?(:widget_beta)
  end

  test "tier 1 (global enabled) false overrides everything else" do
    @feature.update!(enabled: false)
    @feature.feature_organization_accesses.create!(organization: @organization, enabled: true)
    @organization.update_feature!(:widget_beta, enabled: true)

    assert_not @organization.feature_enabled?(:widget_beta)
  end

  test "tier 2 (org access) false or missing overrides tier 3" do
    @feature.update!(enabled: true)
    @organization.update_feature!(:widget_beta, enabled: true)

    assert_not @organization.feature_enabled?(:widget_beta)

    @feature.feature_organization_accesses.create!(organization: @organization, enabled: false)
    assert_not @organization.feature_enabled?(:widget_beta)
  end

  test "tier 3 opt-in false is required when manager_activation_required is true" do
    @feature.update!(enabled: true)
    @feature.feature_organization_accesses.create!(organization: @organization, enabled: true)

    assert_not @organization.feature_enabled?(:widget_beta)
  end

  test "manager_activation_required false ignores tier 3 entirely" do
    @feature.update!(enabled: true, manager_activation_required: false)
    @feature.feature_organization_accesses.create!(organization: @organization, enabled: true)

    assert @organization.feature_enabled?(:widget_beta)
  end

  test "update_feature! merges rather than replaces existing settings" do
    @organization.update_feature!(:widget_beta, enabled: true, note: "first")
    @organization.update_feature!(:widget_beta, enabled: false)

    settings = @organization.reload.feature_settings(:widget_beta)
    assert_equal "first", settings["note"]
    assert_equal false, settings["enabled"]
  end

  test "a NULL features column loads as an empty hash instead of raising" do
    @organization.update_column(:features, nil)

    reloaded = Organization.find(@organization.id)

    assert_equal({}, reloaded.features)
    assert_nothing_raised { reloaded.feature_enabled?(:widget_beta) }
  end
end
