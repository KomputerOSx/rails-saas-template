# frozen_string_literal: true

class BillingPolicy < ApplicationPolicy
  def show?
    permission?
  end

  def manage?
    permission?
  end

  private

  def permission?
    user&.has_permission?("app.billing.manage", organization: record) || false
  end
end
