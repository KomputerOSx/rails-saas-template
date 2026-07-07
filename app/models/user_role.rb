class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :granted_by, class_name: "User", optional: true

  validates :role_id, uniqueness: { scope: :user_id }
  validate :role_must_be_system_scoped

  before_destroy :prevent_revoking_last_system_admin

  private

  def role_must_be_system_scoped
    errors.add(:role, "must be system-scoped") unless role&.system?
  end

  def prevent_revoking_last_system_admin
    return unless role.name == Role::SYSTEM_ADMIN

    other_admins = UserRole.joins(:role)
      .where(roles: { scope: "system", name: Role::SYSTEM_ADMIN })
      .where.not(id: id)

    if other_admins.none?
      errors.add(:base, "cannot revoke the last system admin")
      throw :abort
    end
  end
end
