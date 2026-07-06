# frozen_string_literal: true

class OrganizationPolicy < ApplicationPolicy
  def update?
    user&.has_permission?("app.organization.manage", organization: record) || false
  end
end
