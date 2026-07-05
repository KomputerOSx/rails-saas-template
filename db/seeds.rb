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

if Rails.env.local?
  require "faker"

  # Seed 30 dev users into the same org as the primary dev account
  DEV_OWNER_EMAIL = "ramyarburhan26@gmail.com"

  if (owner = User.find_by(email: DEV_OWNER_EMAIL))
    org = owner.memberships.joins(:membership_roles => :role)
               .where(roles: { name: Role::APP_OWNER, scope: :app })
               .first&.organization

    if org
      # Account state buckets (total = 30)
      # 1. unconfirmed (5)            — signed up, never clicked confirm link
      # 2. confirmed, onboarding stuck (5) — confirmed but never finished onboarding
      # 3. active — regular user (8) — fully onboarded, app_user role
      # 4. active — admin (4)        — fully onboarded, app_admin role
      # 5. locked (4)                — account locked due to failed login attempts
      # 6. active with 2FA (4)       — fully onboarded + TOTP enabled

      states = [
        { count: 5,  label: "unconfirmed" },
        { count: 5,  label: "onboarding_stuck" },
        { count: 8,  label: "active_user" },
        { count: 4,  label: "active_admin" },
        { count: 4,  label: "locked" },
        { count: 4,  label: "active_2fa" }
      ]

      states.each do |bucket|
        bucket[:count].times do
          first = Faker::Name.first_name
          last  = Faker::Name.last_name
          email = Faker::Internet.unique.email(name: "#{first} #{last}")

          next if User.exists?(email: email)

          attrs = {
            email:      email,
            password:   "T5!fH8@zM3#bW6$",
            first_name: first,
            last_name:  last
          }

          case bucket[:label]
          when "unconfirmed"
            attrs[:confirmed_at] = nil

          when "onboarding_stuck"
            attrs[:confirmed_at]           = Faker::Time.between(from: 30.days.ago, to: 7.days.ago)
            attrs[:onboarding_step]        = %w[welcome profile team].sample
            attrs[:onboarding_completed_at] = nil

          when "active_user", "active_admin", "locked", "active_2fa"
            attrs[:confirmed_at]            = Faker::Time.between(from: 60.days.ago, to: 14.days.ago)
            attrs[:onboarding_step]         = "finish"
            attrs[:onboarding_completed_at] = Faker::Time.between(from: 55.days.ago, to: 13.days.ago)
            attrs[:last_sign_in_at]         = Faker::Time.between(from: 10.days.ago, to: 1.day.ago)
          end

          if bucket[:label] == "locked"
            attrs[:failed_login_attempts] = 5
            attrs[:locked_until]          = rand(1..72).hours.from_now
          end

          if bucket[:label] == "active_2fa"
            attrs[:totp_secret]     = ROTP::Base32.random
            attrs[:totp_enabled_at] = Faker::Time.between(from: 30.days.ago, to: 7.days.ago)
          end

          user = User.create!(attrs)

          membership = org.memberships.find_or_create_by!(user: user)

          role = case bucket[:label]
                 when "active_admin" then admin_role
                 else user_role
                 end

          membership.grant_role!(role)
        end
      end

      puts "Seeded 30 dev users into org '#{org.name}' (#{DEV_OWNER_EMAIL})"
    else
      puts "SKIP: no org found for #{DEV_OWNER_EMAIL}"
    end
  else
    puts "SKIP: #{DEV_OWNER_EMAIL} not found — sign up first, then re-run db:seed"
  end
end
