module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    before_action :check_session_expiry
    helper_method :authenticated?, :current_user
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :check_session_expiry, **options
    end
  end

  private

  def authenticated?
    resume_session
  end

  def require_authentication
    resume_session || redirect_to_login
  end

  def resume_session
    # SECURITY: Only resume active (non-expired) sessions
    if session_record = Session.active.find_by(id: cookies.signed[:session_id])
      Current.session = session_record
      if session_record.last_seen_at.blank? || session_record.last_seen_at < 1.minute.ago
        session_record.update_column(:last_seen_at, Time.current)
      end
      true
    else
      cookies.delete(:session_id) if cookies.signed[:session_id].present?
      false
    end
  end

  def check_session_expiry
    return unless authenticated?

    if Current.session.expired?
      AuditLog.create!(
        user: current_user,
        event_type: :session_destroyed,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { reason: "expired" }
      )

      terminate_session
      redirect_to login_path, alert: "Your session has expired. Please log in again."
    end
  end

  def redirect_to_login
    redirect_to login_path, alert: "Please log in to continue."
  end

  def current_user
    Current.user
  end

  def start_new_session_for(user)
    user.sessions.create!(
      user_agent: request.user_agent,
      ip_address: request.remote_ip,
      expires_at: Session::SESSION_DURATION.from_now
    ).tap do |session|
      Current.session = session

      # SECURITY: Set cookie with proper flags.
      # :lax (not :strict) — this cookie is set on the OAuth callback response, which the
      # browser reaches via a cross-site-initiated redirect chain from the provider (e.g.
      # accounts.google.com). A :strict cookie wouldn't be sent on the very next request
      # (the redirect to dashboard_path), so the user would look logged out until a
      # separate, purely same-site navigation (e.g. a manual refresh).
      cookies.signed[:session_id] = {
        value: session.id,
        expires: Session::SESSION_DURATION.from_now,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      }

      AuditLog.create!(
        user: user,
        event_type: :session_created,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { session_id: session.id }
      )
    end
  end

  def terminate_session
    if Current.session
      AuditLog.create!(
        user: current_user,
        event_type: :session_destroyed,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { session_id: Current.session.id, reason: "user_logout" }
      )

      Current.session.destroy
    end

    cookies.delete(:session_id)
  end
end
