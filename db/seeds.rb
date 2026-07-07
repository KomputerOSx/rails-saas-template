# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Role/Permission/RolePermission baseline records normally get synced at boot time by
# config/initializers/rbac_registry.rb, so every process (web, jobs, console) picks up
# config/rbac.yml regardless of the deploy tool. Called again here explicitly, not just
# trusted to have already run: on a brand-new database, db:prepare's schema:load and
# db:seed happen in the same process as an after_initialize that already fired (and
# skipped, since the tables didn't exist yet) before schema:load created them - without
# this call, the lookups below would raise on a database's very first deploy.
RbacRegistry.sync!

system_admin = Role.find_by!(scope: :system, name: Role::SYSTEM_ADMIN)
admin_role   = Role.find_by!(scope: :app, name: Role::APP_ADMIN)
user_role    = Role.find_by!(scope: :app, name: Role::APP_USER)

if Rails.env.local? && ENV["SYSTEM_ADMIN_EMAIL"].present?
  if (user = User.find_by(email: ENV["SYSTEM_ADMIN_EMAIL"]))
    user.grant_role!(system_admin)
  end
end

if Rails.env.development?
  require "faker"

  # Seed 30 dev users into the same org as a generic dev owner account, creating
  # that account (and its personal org) on first run so a fresh database doesn't
  # need a manual sign-up before seeding.
  dev_owner_email = "admin@mail.com"

  owner = User.find_by(email: dev_owner_email)

  if owner.nil?
    owner = User.create!(
      email: dev_owner_email,
      password: "SuperKey99!",
      first_name: "Admin",
      last_name: "User",
      confirmed_at: Time.current
    )
    Organization.create_personal_for!(owner)
  end

  org = owner.memberships.joins(membership_roles: :role)
             .where(roles: { name: Role::APP_OWNER, scope: :app })
             .first&.organization

  if org
    # Account state buckets (total = 30)
    # 1. unconfirmed (5)            - signed up, never clicked confirm link
    # 2. confirmed, onboarding stuck (5) - confirmed but never finished onboarding
    # 3. active - regular user (8) - fully onboarded, app_user role
    # 4. active - admin (4)        - fully onboarded, app_admin role
    # 5. locked (4)                - account locked due to failed login attempts
    # 6. active with 2FA (4)       - fully onboarded + TOTP enabled

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

    puts "Seeded 30 dev users into org '#{org.name}' (#{dev_owner_email})"
  else
    puts "SKIP: no org found for #{dev_owner_email}"
  end
end
