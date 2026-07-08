module Billing
  class PaymentMethodsController < ApplicationController
    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      payment_method = Current.organization.payment_processor&.default_payment_method
      if payment_method.blank?
        return redirect_to billing_path, alert: "No payment method on file."
      end

      payment_method.detach
      payment_method.destroy!
      redirect_to billing_path, notice: "Payment method removed."
    end
  end
end
