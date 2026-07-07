# frozen_string_literal: true

# Gates the whole Admin:: namespace. There's no natural AR record backing this
# check, so `record` is the bare symbol `:system` - Pundit's documented pattern
# for a non-resource authorization (`authorize :system, :manage?`).
class SystemPolicy < ApplicationPolicy
  def manage?
    user&.has_role?(Role::SYSTEM_ADMIN, scope: :system) || false
  end
end
