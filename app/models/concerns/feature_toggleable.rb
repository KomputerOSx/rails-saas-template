# Mixed into the tenant model (Organization). Three independent gates must all pass for
# a feature to be "on": Feature.enabled (global kill switch), FeatureOrganizationAccess.enabled
# (per-org grant), and the org's own opt-in stored in the `features` JSON column (only
# checked when the feature requires it).
module FeatureToggleable
  extend ActiveSupport::Concern

  def feature_enabled?(key)
    feature = Feature.find_by(key: key.to_s)
    return false unless feature&.available_to_organization?(self)

    !feature.manager_activation_required? || feature_org_setting_enabled?(key)
  end

  def feature_available?(key)
    Feature.exists?(key: key.to_s, enabled: true)
  end

  def feature_admin_enabled?(key)
    feature = Feature.find_by(key: key.to_s)
    feature&.available_to_organization?(self) || false
  end

  def feature_org_setting_enabled?(key)
    features.dig(key.to_s, "enabled") == true
  end

  def feature_settings(key)
    features[key.to_s] || {}
  end

  def update_feature!(key, new_settings)
    current = features[key.to_s] || {}
    update!(features: features.merge(key.to_s => current.merge(new_settings.stringify_keys)))
  end
end
