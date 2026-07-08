module Billing
  # Lets the org preview-apply a Stripe promotion code before subscribing/upgrading. The
  # resolved promotion code id is held in the session (not persisted) until it's actually used
  # by SubscriptionsController#create or PaymentMethodsController#subscribe_to_pending_plan, or
  # removed here - it's a checkout-time convenience, not organization state.
  class PromoCodesController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      code = params[:code].to_s.strip
      return respond_with_failure("Enter a promo code.") if code.blank?

      promotion_code = ::Stripe::PromotionCode.list(code: code, active: true, limit: 1, expand: [ "data.coupon" ]).first
      unless promotion_code&.coupon&.valid
        return respond_with_failure("That promo code isn't valid or has expired.")
      end

      session[:promo_code_id] = promotion_code.id
      session[:promo_code_display] = "#{promotion_code.code} - #{describe_coupon(promotion_code.coupon)}"
      respond_with_success("Promo code applied: #{describe_coupon(promotion_code.coupon)}.")
    rescue ::Stripe::StripeError => e
      respond_with_failure(e.message)
    end

    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      session.delete(:promo_code_id)
      session.delete(:promo_code_display)
      respond_with_success("Promo code removed.")
    end

    private

    def describe_coupon(coupon)
      if coupon.percent_off
        percent = coupon.percent_off == coupon.percent_off.to_i ? coupon.percent_off.to_i : coupon.percent_off
        "#{percent}% off"
      elsif coupon.amount_off
        "#{Pay::Currency.format(coupon.amount_off, currency: coupon.currency)} off"
      else
        "Discount applied"
      end
    end

    def respond_with_success(message)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: message, type: "success" }
          render turbo_stream: [
            turbo_stream.replace("promo_code_widget",
              partial: "billing/promo_code_widget",
              locals: { promo_code_id: session[:promo_code_id], promo_code_display: session[:promo_code_display] }),
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
