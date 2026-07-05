module Authorization
  extend ActiveSupport::Concern

  class_methods do
    def require_role(role_name, scope: nil, **options)
      before_action(**options) { require_role!(role_name, scope: scope) }
    end

    def require_permission(permission_key, **options)
      before_action(**options) { require_permission!(permission_key) }
    end

    def require_system_admin(**options)
      require_role(Role::SYSTEM_ADMIN, scope: :system, **options)
    end

    def require_organization_permission(permission_key, **options)
      before_action(**options) { require_organization_permission!(permission_key) }
    end
  end

  private

  def require_role!(role_name, scope: nil)
    return if current_user&.has_role?(role_name, scope: scope)

    deny_authorization!
  end

  def require_permission!(permission_key)
    return if current_user&.has_permission?(permission_key)

    deny_authorization!
  end

  def require_organization_permission!(permission_key)
    return if Current.organization && current_user&.has_permission?(permission_key, organization: Current.organization)

    deny_authorization!
  end

  def deny_authorization!
    log_audit(:authorization_denied, metadata: { path: request.path })
    redirect_to root_path, alert: "You are not authorized to access this page."
  end
end
