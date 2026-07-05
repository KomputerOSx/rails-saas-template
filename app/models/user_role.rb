class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :granted_by, class_name: "User", optional: true

  validates :role_id, uniqueness: { scope: :user_id }
end
