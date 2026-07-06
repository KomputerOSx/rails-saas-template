# frozen_string_literal: true

class OrganizationInvitationPolicy < ApplicationPolicy
  # `create?` authorizes before the invitation exists, so `record` there is the
  # Organization itself; `destroy?` authorizes an actual OrganizationInvitation.
  def create?
    permission?
  end

  def destroy?
    permission?
  end

  private

  def permission?
    user&.has_permission?("app.members.invite", organization: organization) || false
  end

  def organization
    record.is_a?(Organization) ? record : record.organization
  end
end
