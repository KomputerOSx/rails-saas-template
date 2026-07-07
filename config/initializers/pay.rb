Rails.application.config.to_prepare do
  handler = Billing::SubscriptionSyncHandler.new
  Pay::Webhooks.delegator.subscribe "stripe.customer.subscription.created", handler
  Pay::Webhooks.delegator.subscribe "stripe.customer.subscription.updated", handler
  Pay::Webhooks.delegator.subscribe "stripe.customer.subscription.deleted", handler
end
