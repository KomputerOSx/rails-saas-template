# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

system_admin = Role.find_or_create_by!(scope: :system, name: Role::SYSTEM_ADMIN) do |role|
  role.permanent = true
  role.description = "Permanent platform operator role"
end

{
  "system.users.manage" => "Manage user accounts",
  "system.roles.manage" => "View/manage roles and permissions",
  "system.audit_logs.view" => "View audit logs"
}.each do |key, description|
  permission = Permission.find_or_create_by!(key: key) { |p| p.description = description }
  RolePermission.find_or_create_by!(role: system_admin, permission: permission)
end

if Rails.env.local? && ENV["SYSTEM_ADMIN_EMAIL"].present?
  if (user = User.find_by(email: ENV["SYSTEM_ADMIN_EMAIL"]))
    user.grant_role!(system_admin)
  end
end
