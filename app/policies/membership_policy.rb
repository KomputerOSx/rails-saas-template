# frozen_string_literal: true

class MembershipPolicy < ApplicationPolicy
  def destroy?
    permission?("app.members.remove")
  end

  def promote?
    permission?("app.members.promote")
  end

  def demote?
    permission?("app.members.promote")
  end

  def promote_to_owner?
    permission?("app.members.promote_owner")
  end

  def demote_owner?
    permission?("app.members.demote_owner")
  end

  private

  def permission?(key)
    user&.has_permission?(key, organization: record.organization) || false
  end
end
