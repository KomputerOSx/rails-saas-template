class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :granted_by, class_name: "User", optional: true

  validates :role_id, uniqueness: { scope: :user_id }
  validate :role_must_be_system_scoped

  private

  def role_must_be_system_scoped
    errors.add(:role, "must be system-scoped") unless role&.system?
  end
end
