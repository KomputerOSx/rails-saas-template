module Billing
  class PaymentMethodsController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      payment_method = Pay::Stripe::PaymentMethod.sync_setup_intent(params[:setup_intent_id])
      unless payment_method
        return respond_with_failure("Could not save that payment method. Please try again.")
      end

      payment_method.make_default!
      log_audit(:payment_method_updated, resource: Current.organization,
        metadata: { brand: payment_method.brand, last4: payment_method.last4 })

      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: "Payment method saved.", type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(Current.organization, :payment_method_display),
              partial: "billing/payment_method_display", locals: { payment_method: payment_method }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to billing_path, notice: "Payment method saved." }
      end
    rescue Pay::Stripe::Error => e
      respond_with_failure(e.message)
    end

    private

    def respond_with_failure(message)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: message, type: "error" }
          render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash")
        end
        format.html { redirect_to billing_path, alert: message }
      end
    end
  end
end
