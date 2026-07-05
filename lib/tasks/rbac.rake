namespace :rbac do
  desc "Grant the system_admin role to a user by email"
  task :grant_system_admin, [ :email ] => :environment do |_, args|
    user = User.find_by!(email: args[:email])
    role = Role.find_by!(scope: :system, name: Role::SYSTEM_ADMIN)
    user.grant_role!(role)
    AuditLog.create!(user: user, event_type: :role_granted,
      metadata: { role: role.name, actor: "rake:rbac:grant_system_admin" })
    puts "Granted #{role.name} to #{user.email}"
  end
end
