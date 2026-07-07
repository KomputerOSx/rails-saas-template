# Syncs the baseline Role/Permission/RolePermission catalog from config/rbac.yml into
# the database. Invoked at boot (config/initializers/rbac_registry.rb) rather than only
# from db/seeds.rb, since a Kamal deploy's db:prepare only seeds a freshly created
# database - every later deploy of an existing database would otherwise never pick up
# new permissions added to the catalog.
#
# Baseline permissions are attached to a role only at the moment that role is first
# created (see #sync_role!). Once a role exists, this never touches its permission set
# again, so admin edits made via Admin::RolesController persist across every future boot.
class RbacRegistry
  CONFIG_PATH = Rails.root.join("config/rbac.yml")

  def self.sync!
    config = YAML.load_file(CONFIG_PATH)
    sync_permissions!(config.fetch("permissions"))
    sync_roles!(config.fetch("roles"))
  end

  def self.sync_permissions!(permissions)
    permissions.each do |key, description|
      Permission.find_or_create_by!(key: key) { |p| p.description = description }
    end
  end

  def self.sync_roles!(roles_by_scope)
    roles_by_scope.each do |scope, roles|
      roles.each { |name, attrs| sync_role!(scope, name, attrs) }
    end
  end

  def self.sync_role!(scope, name, attrs)
    return if Role.exists?(scope: scope, name: name)

    role = Role.create!(
      scope: scope, name: name,
      permanent: attrs.fetch("permanent", false),
      description: attrs["description"]
    )
    attach_baseline_permissions!(role, attrs.fetch("permissions", []))
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    # Lost a create race against another process booting at the same time - the
    # winner already attached baseline permissions. Nothing to do.
  end

  def self.attach_baseline_permissions!(role, permission_keys)
    permission_keys.each do |key|
      RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(key: key))
    end
  end
end
