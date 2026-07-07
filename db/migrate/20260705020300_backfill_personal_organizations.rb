class BackfillPersonalOrganizations < ActiveRecord::Migration[8.1]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  class MigrationOrganization < ApplicationRecord
    self.table_name = "organizations"
  end

  class MigrationMembership < ApplicationRecord
    self.table_name = "memberships"
  end

  class MigrationMembershipRole < ApplicationRecord
    self.table_name = "membership_roles"
  end

  class MigrationRole < ApplicationRecord
    self.table_name = "roles"
  end

  def up
    owner_role = MigrationRole.find_or_create_by!(scope: "app", name: "owner") do |role|
      role.permanent = true
      role.description = "Organization owner - full control; cannot be removed while sole owner"
    end

    users_without_membership = MigrationUser.where.not(id: MigrationMembership.select(:user_id))

    users_without_membership.find_each do |user|
      base = user.email.to_s.split("@").first.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      base = "org" if base.blank?
      slug = base
      suffix = 2
      while MigrationOrganization.exists?(slug: slug)
        slug = "#{base}-#{suffix}"
        suffix += 1
      end

      name = base.tr("-", " ").split.map(&:capitalize).join(" ")

      organization = MigrationOrganization.create!(name: name, slug: slug)
      membership = MigrationMembership.create!(user_id: user.id, organization_id: organization.id)
      MigrationMembershipRole.create!(membership_id: membership.id, role_id: owner_role.id)
    end
  end

  def down
    # Data is intentionally left in place - nothing to revert.
  end
end
