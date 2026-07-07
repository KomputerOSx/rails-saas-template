# frozen_string_literal: true

# Gates the whole Admin:: namespace. There's no natural AR record backing this
# check, so `record` is the bare symbol `:system` - Pundit's documented pattern
# for a non-resource authorization (`authorize :system, :manage?`).
#
# `manage?` is the coarse namespace entry gate (any system-scoped role gets past
# Admin::BaseController); the other predicates below gate individual controllers
# behind the specific system.* permission that role's permissions actually grant,
# so e.g. disabling system.users.manage on a role locks its holders out of
# Admin::UsersController even though they can still reach the namespace.
class SystemPolicy < ApplicationPolicy
  def manage?
    user&.system_operator? || false
  end

  def manage_users?
    user&.has_permission?("system.users.manage") || false
  end

  def manage_roles?
    user&.has_permission?("system.roles.manage") || false
  end

  def view_audit_logs?
    user&.has_permission?("system.audit_logs.view") || false
  end
end
