module Billing
  # Runs after Pay has already synced the Stripe event into its own tables (Pay::Webhooks
  # subscribers fire after Pay's own processing), so it's safe to read Pay::Subscription here.
  class SubscriptionSyncHandler
    EVENT_TYPE_MAP = {
      "customer.subscription.created" => "subscription_created",
      "customer.subscription.updated" => "subscription_updated",
      "customer.subscription.deleted" => "subscription_cancelled"
    }.freeze

    def call(event)
      pay_subscription = Pay::Subscription.find_by(processor_id: event.data.object.id)
      return unless pay_subscription
      return unless pay_subscription.customer.owner_type == "Organization"

      Billing::ReconcileOrganizationJob.perform_later(
        pay_subscription.customer.owner_id,
        audit_event_type: EVENT_TYPE_MAP.fetch(event.type, "subscription_updated")
      )
    end
  end
end
