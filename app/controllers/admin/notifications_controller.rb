module Admin
  class NotificationsController < BaseController
    def index
      @q      = params[:q].to_s.strip
      @status = params[:status].to_s.strip

      @notifications = Notification.recent.includes(:created_by, :notification_recipients)
      @notifications = @notifications.where("title LIKE ?", "%#{Notification.sanitize_sql_like(@q)}%") if @q.present?
      @notifications = @notifications.active    if @status == "active"
      @notifications = @notifications.withdrawn if @status == "withdrawn"
    end

    def new
      @users = User.order(:email)
    end

    def create
      recipients = if params[:notification][:send_to_all] == "1"
        User.all
      else
        User.where(id: Array(params[:notification][:user_ids]).reject(&:blank?))
      end

      notification = Notification.deliver!(
        title: params[:notification][:title],
        body: params[:notification][:body],
        to: recipients,
        created_by: current_user
      )
      log_audit(:notification_created, resource: notification, metadata: { recipient_count: notification.notification_recipients.count })
      redirect_to admin_notifications_path, notice: "Notification sent to #{notification.notification_recipients.count} user(s)."
    rescue ArgumentError => e
      @users = User.order(:email)
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    def withdraw
      notification = Notification.active.find(params[:id])
      notification.withdraw!
      log_audit(:notification_withdrawn, resource: notification)
      redirect_to admin_notifications_path, notice: "Notification withdrawn."
    end
  end
end
