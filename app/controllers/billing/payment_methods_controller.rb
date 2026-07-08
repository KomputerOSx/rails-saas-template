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

      if params[:plan].present?
        subscribe_to_pending_plan
      else
        respond_with_success("Payment method saved.", payment_method: payment_method)
      end
    rescue Pay::Stripe::Error => e
      respond_with_failure(e.message)
    end

    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      payment_method = Current.organization.payment_processor.default_payment_method
      return respond_with_failure("No payment method on file.") unless payment_method

      unless Current.organization.current_plan.free?
        return respond_with_failure("You can't remove your payment method while subscribed to a paid plan. Cancel your subscription first.")
      end

      payment_method.detach
      payment_method.destroy
      log_audit(:payment_method_removed, resource: Current.organization,
        metadata: { brand: payment_method.brand, last4: payment_method.last4 })

      respond_with_success("Payment method removed.", payment_method: nil)
    rescue Pay::Stripe::Error => e
      respond_with_failure(e.message)
    end

    private

    # A card that was just added specifically to subscribe to a plan needs the whole page
    # (Current Plan section, not just the payment method card) to refresh, so this always
    # does a full redirect rather than a turbo_stream partial update - Turbo Drive follows a
    # plain redirect response as a full visit regardless of the triggering form's format.
    def subscribe_to_pending_plan
      plan = ::Billing::Plans.find(params[:plan])
      organization = Current.organization
      return redirect_to billing_path, notice: "Payment method saved." if plan.nil? || plan.free? || plan.resolved_stripe_price_id(organization.billing_currency).blank?

      result = organization.subscribe_to!(plan)
      log_audit(result == :created ? :subscription_created : :subscription_updated, resource: organization, metadata: { plan: plan.key })
      redirect_to billing_path, notice: "Payment method saved and subscribed to the #{plan.name} plan."
    rescue Pay::ActionRequired, Pay::InvalidPaymentMethod
      redirect_to billing_path, alert: "Payment method saved, but your card needs additional verification before we can subscribe. Please try upgrading again."
    rescue Pay::Stripe::Error => e
      redirect_to billing_path, alert: "Payment method saved, but subscribing failed: #{e.message}"
    end

    def respond_with_success(message, payment_method:)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: message, type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(Current.organization, :payment_method_display),
              partial: "billing/payment_method_display", locals: { payment_method: payment_method }),
            turbo_stream.update("flash_messages", partial: "shared/flash")
          ]
        end
        format.html { redirect_to billing_path, notice: message }
      end
    end

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
