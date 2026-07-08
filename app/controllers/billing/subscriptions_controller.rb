module Billing
  class SubscriptionsController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      plan = ::Billing::Plans.find(params[:plan])
      return redirect_with_alert("That plan isn't available.") if plan.nil? || plan.free? || plan.resolved_stripe_price_id.blank?

      organization = Current.organization
      payment_method = organization.payment_processor.default_payment_method
      return redirect_with_alert("Add a payment method before subscribing.") unless payment_method

      if organization.current_plan.free?
        organization.payment_processor.subscribe(
          plan: plan.resolved_stripe_price_id, default_payment_method: payment_method.processor_id, quantity: 1
        )
        log_audit(:subscription_created, resource: organization, metadata: { plan: plan.key })
        message = "Subscribed to the #{plan.name} plan."
      else
        organization.payment_processor.subscription.swap(plan.resolved_stripe_price_id)
        log_audit(:subscription_updated, resource: organization, metadata: { plan: plan.key })
        message = "Switched to the #{plan.name} plan."
      end

      redirect_to billing_path, notice: message
    rescue Pay::ActionRequired, Pay::InvalidPaymentMethod
      redirect_with_alert("Your card needs additional verification. Please update your payment method and try again.")
    rescue Pay::Stripe::Error => e
      redirect_with_alert(e.message)
    end

    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      subscription = Current.organization.payment_processor.subscription
      return redirect_with_alert("No active subscription to cancel.") unless subscription&.active?

      if Rails.env.production?
        subscription.cancel
        message = "Your subscription will end on #{subscription.ends_at&.to_date&.to_fs(:long)}."
      else
        # Not production: kill it immediately rather than waiting for period end, so the
        # billing/limit flows are easy to re-test without waiting out a billing cycle.
        subscription.cancel_now!
        message = "Subscription cancelled."
      end

      log_audit(:subscription_cancelled, resource: Current.organization, metadata: { immediate: !Rails.env.production? })
      redirect_to billing_path, notice: message
    rescue Pay::Stripe::Error => e
      redirect_with_alert(e.message)
    end

    private

    def redirect_with_alert(message)
      redirect_to billing_path, alert: message
    end
  end
end
