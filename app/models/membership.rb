class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  has_many :membership_roles, dependent: :destroy
  has_many :roles, through: :membership_roles

  validates :user_id, uniqueness: { scope: :organization_id }

  def has_role?(name, scope: nil)
    scoped = scope ? roles.where(scope: scope.to_s) : roles
    scoped.exists?(name: name.to_s)
  end

  def has_permission?(key)
    roles.joins(:permissions).exists?(permissions: { key: key.to_s })
  end

  def grant_role!(role, granted_by: nil)
    membership_roles.find_or_create_by!(role: role) { |mr| mr.granted_by = granted_by }
  end

  def revoke_role!(role)
    membership_roles.find_by(role: role)&.destroy
  end
end
