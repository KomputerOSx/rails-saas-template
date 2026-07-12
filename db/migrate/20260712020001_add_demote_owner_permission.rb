class AddDemoteOwnerPermission < ActiveRecord::Migration[8.1]
  class Permission < ActiveRecord::Base; end
  class Role < ActiveRecord::Base; end
  class RolePermission < ActiveRecord::Base; end

  # See 20260712010001_add_promote_owner_permission.rb - RbacRegistry only attaches baseline
  # permissions to a role at the moment that role is first created, so an existing `owner`
  # role needs this new permission attached explicitly (docs/rbac.md #13-14).
  def up
    permission = Permission.find_or_create_by!(key: "app.members.demote_owner") do |p|
      p.description = "Demote an owner to admin"
    end

    Role.where(scope: "app", name: "owner").find_each do |owner_role|
      RolePermission.find_or_create_by!(role_id: owner_role.id, permission_id: permission.id)
    end
  end

  def down
    permission = Permission.find_by(key: "app.members.demote_owner")
    return unless permission

    RolePermission.where(permission_id: permission.id).delete_all
    permission.destroy
  end
end
