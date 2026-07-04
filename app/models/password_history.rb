class PasswordHistory < ApplicationRecord
  belongs_to :user

  validates :password_digest, presence: true

  def self.password_used_before?(user, password)
    user.password_histories
      .order(created_at: :desc)
      .limit(10)
      .any? { |ph| BCrypt::Password.new(ph.password_digest) == password }
  end
end
