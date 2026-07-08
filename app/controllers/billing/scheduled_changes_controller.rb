module Billing
  # "Keep my current plan" - undoes a scheduled downgrade before it takes effect by releasing
  # the Stripe Subscription Schedule; the subscription then renews on its current price as if
  # the downgrade was never requested.
  class ScheduledChangesController < ApplicationController
    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      organization = Current.organization
      return redirect_to billing_path, alert: "No scheduled plan change to cancel." unless organization.scheduled_downgrade?

      pending = organization.pending_plan
      organization.cancel_scheduled_downgrade!
      log_audit(:subscription_downgrade_cancelled, resource: organization,
        metadata: { plan: pending&.key })

      redirect_to billing_path, notice: "Scheduled plan change cancelled - you'll stay on the #{organization.current_plan.name} plan."
    rescue Pay::Stripe::Error => e
      redirect_to billing_path, alert: e.message
    end
  end
end
