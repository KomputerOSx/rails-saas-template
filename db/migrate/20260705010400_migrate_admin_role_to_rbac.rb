class MigrateAdminRoleToRbac < ActiveRecord::Migration[8.1]
  class MigrationRole < ApplicationRecord
    self.table_name = "roles"
  end

  class MigrationUserRole < ApplicationRecord
    self.table_name = "user_roles"
  end

  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    system_admin = MigrationRole.find_or_create_by!(scope: "system", name: "system_admin") do |role|
      role.permanent = true
      role.description = "Permanent platform operator role"
    end

    MigrationUser.where(role: "admin").find_each do |user|
      MigrationUserRole.find_or_create_by!(user_id: user.id, role_id: system_admin.id)
    end
  end

  def down
    # Data is intentionally left in place; the users.role column removal is reverted separately.
  end
end
