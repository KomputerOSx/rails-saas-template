module Admin
  class DashboardController < BaseController
    def index
      @user_count = User.count
      @new_user_count = User.where(created_at: 7.days.ago..).count
      @organization_count = Organization.count
      @role_count = Role.count
      @permission_count = Permission.count
      @audit_log_count = AuditLog.count
      @security_event_count = AuditLog.security_events.where(created_at: 24.hours.ago..).count
      @notification_count = Notification.active.count
      @maintenance_status = MaintenanceMode.status
      @recent_audit_logs = AuditLog.recent.includes(:user).limit(6)
    end
  end
end
