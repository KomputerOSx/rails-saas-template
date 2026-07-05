class NotificationRecipientsController < ApplicationController
  before_action :set_notification_recipient, only: [ :mark_read, :destroy ]

  def index
    @notification_recipients = current_user.notification_recipients.inbox.order(created_at: :desc).includes(:notification)
  end

  def mark_read
    @notification_recipient.mark_read!
    redirect_back fallback_location: root_path
  end

  def mark_all_read
    current_user.notification_recipients.inbox.unread.update_all(read_at: Time.current)
    redirect_back fallback_location: root_path
  end

  def destroy
    @notification_recipient.dismiss!
    redirect_back fallback_location: root_path
  end

  private

  def set_notification_recipient
    @notification_recipient = current_user.notification_recipients.find(params[:id])
  end
end
