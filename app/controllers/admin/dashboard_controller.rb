module Admin
  class DashboardController < BaseController
    def index
      @user_count = User.count
      @role_count = Role.count
      @recent_audit_logs = AuditLog.recent.limit(10)
    end
  end
end
