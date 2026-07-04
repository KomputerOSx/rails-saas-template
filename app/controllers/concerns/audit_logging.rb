module AuditLogging
  extend ActiveSupport::Concern

  private

  def log_audit(event_type, user: current_user, resource: nil, metadata: {})
    AuditLog.create!(
      user: user,
      event_type: event_type,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      metadata: { controller: "#{params[:controller]}##{params[:action]}" }.merge(metadata)
    )
  rescue => e
    Rails.logger.error "[AuditLog] #{e.class}: #{e.message} — event=#{event_type} user=#{user&.id}"
  end
end
