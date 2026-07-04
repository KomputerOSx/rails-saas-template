class TwoFactorChallenge < ApplicationRecord
  belongs_to :user

  enum :delivery_method, { email: "email", totp: "totp" }, prefix: true

  scope :active, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def active?
    used_at.blank? && !expired?
  end
end
