# Syncs the Feature catalog from config/features.yml into the database at boot. See
# RbacRegistry for the identical rationale (a Kamal deploy's db:prepare only seeds a
# freshly created database, so this must also run from an after_initialize hook to
# reach every later deploy of an existing database).
#
# `enabled` is only set on creation - an admin's toggle in Admin::FeaturesController is
# never overwritten by a redeploy; only genuinely new keys defined in the YAML get
# inserted.
class FeatureRegistry
  CONFIG_PATH = Rails.root.join("config/features.yml")

  def self.sync!
    config = YAML.load_file(CONFIG_PATH) || {}

    config.each do |key, attrs|
      Feature.find_or_create_by!(key: key) do |f|
        f.name = attrs.fetch("name")
        f.description = attrs["description"]
        f.manager_activation_required = attrs.fetch("manager_activation_required", true)
        f.enabled = false
      end
    end
  end
end
