class NotificationRecipientsController < ApplicationController
  before_action :set_notification_recipient, only: [ :mark_read, :destroy ]

  def index
    @notification_recipients = inbox_recipients
  end

  def mark_read
    @notification_recipient.mark_read!
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(dom_id(@notification_recipient), partial: "notification_recipients/recipient",
                                locals: { recipient: @notification_recipient }),
          turbo_stream.replace("notification_unread_badge", partial: "shared/notification_badge",
                                locals: { unread_count: current_user.unread_notification_count })
        ]
      end
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def mark_all_read
    current_user.notification_recipients.inbox.unread.update_all(read_at: Time.current)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: inbox_replace_stream }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  def destroy
    @notification_recipient.dismiss!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: inbox_replace_stream }
      format.html { redirect_back fallback_location: root_path }
    end
  end

  private

  def set_notification_recipient
    @notification_recipient = current_user.notification_recipients.find(params[:id])
  end

  def inbox_recipients
    current_user.notification_recipients.inbox.order(created_at: :desc).includes(:notification)
  end

  # Dismiss/mark-all-read can cross the 0-unread or 0-remaining boundary, so we
  # always replace the whole inbox container rather than patching individual rows -
  # simpler than conditionally branching on whether this action crossed an empty-state
  # boundary, and the query cost is trivial for a per-user notification inbox.
  def inbox_replace_stream
    [
      turbo_stream.replace("notifications_inbox", partial: "notification_recipients/inbox",
                            locals: { notification_recipients: inbox_recipients }),
      turbo_stream.replace("notification_unread_badge", partial: "shared/notification_badge",
                            locals: { unread_count: current_user.unread_notification_count })
    ]
  end
end
