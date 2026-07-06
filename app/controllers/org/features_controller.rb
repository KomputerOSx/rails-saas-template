module Org
  class FeaturesController < BaseController
    def index
      authorize Current.organization, :update?, policy_class: OrganizationPolicy

      @features = Feature.available_to_organization(Current.organization)
    end

    def update
      authorize Current.organization, :update?, policy_class: OrganizationPolicy

      # Only ever writes keys this org is actually granted (tiers 1+2) — a member can't
      # use a crafted request to write arbitrary keys into the features JSON column.
      available_keys = Feature.available_to_organization(Current.organization).pluck(:key)
      submitted = params.fetch(:features, {}).to_unsafe_h

      submitted.each do |key, attrs|
        next unless available_keys.include?(key)

        enabled = ActiveModel::Type::Boolean.new.cast(attrs["enabled"])
        Current.organization.update_feature!(key, enabled: enabled)
      end

      log_audit(:organization_feature_settings_updated, resource: Current.organization)
      redirect_to org_features_path, notice: "Feature settings updated."
    end
  end
end
