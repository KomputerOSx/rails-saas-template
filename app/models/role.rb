class Role < ApplicationRecord
  SYSTEM_ADMIN = "system_admin"
  APP_OWNER = "owner"
  APP_ADMIN = "admin"
  APP_USER = "user"

  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles
  has_many :membership_roles, dependent: :destroy
  has_many :memberships, through: :membership_roles

  enum :scope, { app: "app", system: "system" }, default: "app"

  validates :name, presence: true, format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :name, uniqueness: { scope: :scope }

  before_update :prevent_permanent_rename, if: :name_changed?
  before_destroy :prevent_permanent_deletion

  private

  def prevent_permanent_rename
    if permanent?
      errors.add(:base, "cannot rename a permanent role")
      throw :abort
    end
  end

  def prevent_permanent_deletion
    if permanent?
      errors.add(:base, "cannot delete a permanent role")
      throw :abort
    end
  end
end
