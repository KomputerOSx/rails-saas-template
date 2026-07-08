module Billing
  class ReconcileOrganizationJob < ApplicationJob
    queue_as :default

    def perform(organization_id, audit_event_type: "subscription_updated")
      organization = Organization.find_by(id: organization_id)
      return unless organization

      subscription = organization.payment_processor&.subscription

      # A scheduled downgrade or price migration is held locally (pending_plan_change_at, plus
      # either pending_plan_key or pending_price_cents) until Stripe actually flips the price at
      # the subscription's renewal - once that effective time has passed (or there's nothing
      # active anymore, e.g. cancelled before the change landed), the pending state is spent and
      # must be cleared so the "changing to X on <date>" notice goes away. Time-based rather than
      # comparing the resulting price/plan directly, since this same webhook fires for both kinds
      # of pending change and a schedule's phase transition is exactly what triggers it.
      if organization.pending_plan_change_at.present?
        organization.clear_pending_plan_change! if organization.pending_plan_change_at.past? || !subscription&.active?
      end

      # An active subscription on a price this app doesn't know (e.g. someone hand-swapped the
      # subscription to a custom Price in the Stripe Dashboard) silently falls back to Free
      # limits - loud logging is the safety net. Use a Coupon for custom pricing instead.
      unrecognized_price = subscription&.active? && Billing::Plans.for_stripe_price(subscription.processor_plan).nil?
      if unrecognized_price
        Rails.logger.warn(
          "[Billing] Organization #{organization.id} has an active subscription on unrecognized " \
          "Stripe price #{subscription.processor_plan} - treating as Free for limits. Use a Coupon " \
          "for per-customer discounts, or add this price to Billing::Plans."
        )
      end

      was_over_limit = organization.over_member_limit?
      now_over_limit = organization.member_count_with_pending > organization.member_limit

      if now_over_limit && !was_over_limit
        organization.update!(over_member_limit_at: Time.current)
      elsif !now_over_limit && was_over_limit
        organization.update!(over_member_limit_at: nil)
      end

      metadata = { plan: organization.current_plan.key, over_member_limit: now_over_limit }
      metadata[:unrecognized_price] = subscription.processor_plan if unrecognized_price

      AuditLog.create!(
        event_type: audit_event_type,
        resource_type: "Organization",
        resource_id: organization.id,
        metadata: metadata
      )
    end
  end
end
