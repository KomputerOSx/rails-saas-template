module Billing
  class ReconcileOrganizationJob < ApplicationJob
    queue_as :default

    def perform(organization_id, audit_event_type: "subscription_updated")
      organization = Organization.find_by(id: organization_id)
      return unless organization

      was_over_limit = organization.over_member_limit?
      now_over_limit = organization.member_count_with_pending > organization.member_limit

      if now_over_limit && !was_over_limit
        organization.update!(over_member_limit_at: Time.current)
      elsif !now_over_limit && was_over_limit
        organization.update!(over_member_limit_at: nil)
      end

      AuditLog.create!(
        event_type: audit_event_type,
        resource_type: "Organization",
        resource_id: organization.id,
        metadata: { plan: organization.current_plan.key, over_member_limit: now_over_limit }
      )
    end
  end
end
