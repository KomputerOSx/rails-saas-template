class MembershipRole < ApplicationRecord
  belongs_to :membership
  belongs_to :role
  belongs_to :granted_by, class_name: "User", optional: true

  validates :role_id, uniqueness: { scope: :membership_id }
  validate :role_must_be_app_scoped

  before_destroy :prevent_removing_last_owner

  private

  def role_must_be_app_scoped
    errors.add(:role, "must be app-scoped") unless role&.app?
  end

  def prevent_removing_last_owner
    return unless role.name == Role::APP_OWNER

    other_owners = membership.organization.membership_roles
      .joins(:role).where(roles: { scope: "app", name: Role::APP_OWNER })
      .where.not(id: id)

    if other_owners.none?
      errors.add(:base, "cannot remove the organization's last owner")
      throw :abort
    end

    # Extension point for ownership transfer (NOT implemented in this template):
    # grant the `owner` role to the new owner's Membership FIRST, THEN revoke the
    # previous owner's MembershipRole. This guard's "other_owners" query then finds
    # the new owner and permits the revoke - no change needed here, just a new
    # controller action performing the grant-then-revoke pair in one transaction.
  end
end
