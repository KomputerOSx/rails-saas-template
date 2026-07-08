module Billing
  # Un-cancels a subscription during its grace period (cancelled but not yet ended) - Stripe
  # flips cancel_at_period_end back off and billing continues as if the cancel never happened.
  class SubscriptionResumesController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      subscription = Current.organization.payment_processor&.subscription
      unless subscription&.on_grace_period?
        return redirect_to billing_path, alert: "There's no cancelled subscription to resume."
      end

      subscription.resume
      log_audit(:subscription_resumed, resource: Current.organization,
        metadata: { plan: Current.organization.current_plan.key })

      redirect_to billing_path, notice: "Welcome back! Your #{Current.organization.current_plan.name} plan will continue as before."
    rescue Pay::Stripe::Error => e
      redirect_to billing_path, alert: e.message
    end
  end
end
