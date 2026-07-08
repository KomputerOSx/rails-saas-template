module Billing
  class SubscriptionsController < ApplicationController
    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      subscription = Current.organization.payment_processor&.subscription
      unless subscription&.active?
        return redirect_to billing_path, alert: "There's no active subscription to cancel."
      end

      subscription.cancel
      redirect_to billing_path, notice: "Your subscription will end on #{subscription.ends_at.strftime("%B %-d, %Y")}. You'll keep access until then."
    end

    def resume
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      subscription = Current.organization.payment_processor&.subscription
      unless subscription&.on_grace_period?
        return redirect_to billing_path, alert: "There's no cancellation to undo."
      end

      subscription.resume
      redirect_to billing_path, notice: "Your subscription has been resumed."
    end
  end
end
