module Billing
  class PortalSessionsController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      if Current.organization.payment_processor.processor_id.blank?
        return redirect_to billing_path, alert: "No billing account yet - upgrade to a paid plan first."
      end

      portal = Current.organization.payment_processor.billing_portal(return_url: billing_url)
      redirect_to portal.url, allow_other_host: true, status: :see_other
    end
  end
end
