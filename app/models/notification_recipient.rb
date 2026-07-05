class NotificationRecipient < ApplicationRecord
  belongs_to :notification
  belongs_to :user

  validates :user_id, uniqueness: { scope: :notification_id }

  scope :unread, -> { where(read_at: nil) }
  scope :not_dismissed, -> { where(dismissed_at: nil) }
  scope :inbox, -> { not_dismissed.joins(:notification).merge(Notification.active) }

  def mark_read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def dismiss!
    update!(dismissed_at: Time.current)
  end
end
