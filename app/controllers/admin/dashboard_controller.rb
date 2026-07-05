module Admin
  class DashboardController < BaseController
    def index
      @user_count = User.count
      @role_count = Role.count
      @permission_count = Permission.count
      @audit_log_count = AuditLog.count
    end
  end
end
