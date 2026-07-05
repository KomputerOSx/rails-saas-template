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

# --- Organization-scoped (app) roles ---
# owner: permanent, granted automatically to whoever creates an Organization (see
#   Organization.create_personal_for!). Cannot be renamed/deleted (Role#permanent) and
#   cannot be revoked from the org's last owner (MembershipRole's owner-protection guard).
# admin: promotable/demotable by an owner. Its permission set below is just a plain
#   array — nothing in the codebase branches on the role name "admin", so downstream
#   forks can change what admins can do by editing this list, not by changing code.
# user: the default role granted to invited members. No elevated permissions.
owner_role = Role.find_or_create_by!(scope: :app, name: Role::APP_OWNER) do |role|
  role.permanent = true
  role.description = "Organization owner — full control; cannot be removed while sole owner"
end

admin_role = Role.find_or_create_by!(scope: :app, name: Role::APP_ADMIN) do |role|
  role.description = "Organization admin — can invite and remove members"
end

user_role = Role.find_or_create_by!(scope: :app, name: Role::APP_USER) do |role|
  role.description = "Organization member — standard product access"
end

{
  "app.members.invite" => "Invite people to the organization",
  "app.members.remove" => "Remove members from the organization",
  "app.members.promote" => "Promote/demote members between admin and user",
  "app.organization.manage" => "Manage organization settings",
  "app.billing.manage" => "Manage billing and subscription (placeholder — no billing gem yet)"
}.each do |key, description|
  Permission.find_or_create_by!(key: key) { |p| p.description = description }
end

{
  owner_role => %w[app.members.invite app.members.remove app.members.promote app.organization.manage app.billing.manage],
  admin_role => %w[app.members.invite app.members.remove],
  user_role => []
}.each do |role, keys|
  keys.each do |key|
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(key: key))
  end
end
