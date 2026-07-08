module Billing
  class SetupIntentsController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      intent = Current.organization.payment_processor.create_setup_intent(usage: "off_session")
      render json: { client_secret: intent.client_secret }
    end
  end
end
