class Session < ApplicationRecord
  belongs_to :user

  SESSION_DURATION = 12.hours

  before_create do
    self.user_agent = Current.user_agent
    self.ip_address = Current.ip_address
    self.expires_at = SESSION_DURATION.from_now
  end

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def time_remaining
    return 0 if expired?
    ((expires_at - Time.current) / 60).to_i
  end

  def self.cleanup_expired!
    expired.destroy_all
  end
end
