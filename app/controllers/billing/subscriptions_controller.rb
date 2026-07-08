module Billing
  class SubscriptionsController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      plan = ::Billing::Plans.find(params[:plan])
      organization = Current.organization
      return redirect_with_alert("That plan isn't available.") if plan.nil? || plan.free? || plan.resolved_stripe_price_id(organization.billing_currency).blank?
      return redirect_with_alert("You're already on the #{plan.name} plan.") if plan.key == organization.current_plan.key
      return redirect_with_alert("Add a payment method before subscribing.") unless organization.payment_processor.default_payment_method

      case organization.change_plan!(plan, promotion_code: session[:promo_code_id])
      when :created
        clear_promo_code!
        log_audit(:subscription_created, resource: organization, metadata: { plan: plan.key })
        redirect_to billing_path, notice: "Subscribed to the #{plan.name} plan."
      when :trial_started
        clear_promo_code!
        log_audit(:subscription_created, resource: organization, metadata: { plan: plan.key, trial: true })
        redirect_to billing_path, notice: "Your #{Organization::TRIAL_DAYS}-day free trial of the #{plan.name} plan has started."
      when :upgraded
        clear_promo_code!
        log_audit(:subscription_updated, resource: organization, metadata: { plan: plan.key })
        redirect_to billing_path, notice: "Switched to the #{plan.name} plan. The prorated difference for the rest of this period has been charged to your card."
      when :downgrade_scheduled
        log_audit(:subscription_downgrade_scheduled, resource: organization, metadata: { plan: plan.key })
        change_date = organization.pending_plan_change_at&.to_date&.to_fs(:long) || "your next billing date"
        redirect_to billing_path, notice: "Your plan will change to #{plan.name} on #{change_date}. Until then you keep your current plan."
      end
    rescue Pay::ActionRequired, Pay::InvalidPaymentMethod
      redirect_with_alert("Your card needs additional verification. Please update your payment method and try again.")
    rescue Pay::Stripe::Error => e
      redirect_with_alert(e.message)
    end

    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      organization = Current.organization
      subscription = organization.payment_processor.subscription
      return redirect_with_alert("No active subscription to cancel.") unless subscription&.active?
      return redirect_with_alert("Your subscription is already set to cancel.") if subscription.on_grace_period?

      cancelled_subscription = organization.cancel_subscription!
      log_audit(:subscription_cancelled, resource: organization, metadata: { plan: organization.current_plan.key })

      end_date = cancelled_subscription.ends_at&.to_date&.to_fs(:long) || "the end of your current billing period"
      redirect_to billing_path, notice: "Your #{organization.current_plan.name} plan will end on #{end_date}. You can resume any time before then."
    rescue Pay::Stripe::Error => e
      redirect_with_alert(e.message)
    end

    private

    def clear_promo_code!
      session.delete(:promo_code_id)
      session.delete(:promo_code_display)
    end

    def redirect_with_alert(message)
      redirect_to billing_path, alert: message
    end
  end
end
