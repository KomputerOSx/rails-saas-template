module Admin
  class AuditLogsController < BaseController
    before_action { authorize :system, :view_audit_logs?, policy_class: SystemPolicy }

    def index
      @q          = params[:q].to_s.strip
      @event_type = params[:event_type].to_s.strip

      @audit_logs = AuditLog.recent.includes(:user)

      if @q.present?
        like = "%#{AuditLog.sanitize_sql_like(@q)}%"
        matching_user_ids = User.where("email LIKE ?", like).pluck(:id)
        @audit_logs = @audit_logs.where(
          "audit_logs.ip_address LIKE :like OR audit_logs.user_id IN (:ids)",
          like: like, ids: matching_user_ids.presence || [ -1 ]
        )
      end

      @audit_logs = @audit_logs.where(event_type: @event_type) if AuditLog.event_types.key?(@event_type)

      @audit_logs = @audit_logs.limit(100)
    end

    def show
      @audit_log = AuditLog.find(params[:id])
      @related_logs = if @audit_log.user
        AuditLog.where(user: @audit_log.user).where.not(id: @audit_log.id).recent.limit(10)
      else
        AuditLog.none
      end
    end
  end
end
