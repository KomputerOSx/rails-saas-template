module Billing
  class CheckoutsController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      plan = ::Billing::Plans.find(params[:plan])
      if plan.nil? || plan.free? || plan.resolved_stripe_price_id.blank?
        return redirect_to billing_path, alert: "That plan isn't available for checkout."
      end

      session = Current.organization.payment_processor.checkout(
        mode: "subscription",
        line_items: plan.resolved_stripe_price_id,
        success_url: billing_url(checkout: "success"),
        cancel_url: billing_url(checkout: "cancelled")
      )
      redirect_to session.url, allow_other_host: true, status: :see_other
    end
  end
end
