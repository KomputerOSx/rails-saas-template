module Billing
  # Applying a code means different things depending on billing state:
  # - No active subscription yet (Free): resolved id is held in the session (not persisted)
  #   until it's actually used by SubscriptionsController#create or
  #   PaymentMethodsController#subscribe_to_pending_plan - it's a checkout-time convenience,
  #   not organization state.
  # - Already subscribed: applied straight to the live Stripe subscription right away
  #   (Organization#apply_promotion_code!), so an existing customer can be given a discount
  #   without changing plans - the session then just mirrors what's live, purely for display,
  #   and "Remove" strips it back off the subscription instead of only clearing the session.
  class PromoCodesController < ApplicationController
    def create
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      code = params[:code].to_s.strip
      return respond_with_failure("Enter a promo code.") if code.blank?

      promotion_code = ::Stripe::PromotionCode.list(
        code: code, active: true, limit: 1, expand: [ "data.coupon", "data.promotion.coupon" ]
      ).first
      coupon = resolve_coupon(promotion_code)
      unless coupon&.valid
        return respond_with_failure("That promo code isn't valid or has expired.")
      end

      organization = Current.organization
      description = describe_coupon(coupon)

      if organization.current_plan.free?
        session[:promo_code_id] = promotion_code.id
        session[:promo_code_display] = "#{promotion_code.code} - #{description}"
        session[:promo_code_applied_live] = false
        respond_with_success("Promo code applied: #{description}. It'll be used when you subscribe.")
      else
        organization.apply_promotion_code!(promotion_code.id)
        session[:promo_code_id] = promotion_code.id
        session[:promo_code_display] = "#{promotion_code.code} - #{description}"
        session[:promo_code_applied_live] = true
        log_audit(:promotion_code_applied, resource: organization, metadata: { code: promotion_code.code })
        respond_with_success("Promo code applied: #{description}. Your next bill reflects this.")
      end
    rescue ::Stripe::StripeError, Pay::Stripe::Error => e
      respond_with_failure(e.message)
    end

    def destroy
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      organization = Current.organization
      if session[:promo_code_applied_live]
        organization.remove_promotion_code!
        log_audit(:promotion_code_removed, resource: organization)
      end

      session.delete(:promo_code_id)
      session.delete(:promo_code_display)
      session.delete(:promo_code_applied_live)
      respond_with_success("Promo code removed.")
    rescue Pay::Stripe::Error => e
      respond_with_failure(e.message)
    end

    private

    # Stripe moved PromotionCode#coupon to a polymorphic PromotionCode#promotion.coupon as of
    # the 2025-09-30 ("Clover") API version - #coupon no longer exists at all on that version,
    # it's not just deprecated-but-present, so calling it directly raises NoMethodError rather
    # than returning nil. Prefer the new field; fall back to the old one for any account still
    # pinned to an older API version where #promotion doesn't exist.
    def resolve_coupon(promotion_code)
      return nil unless promotion_code

      if promotion_code.respond_to?(:promotion) && promotion_code.promotion&.type == "coupon"
        promotion_code.promotion.coupon
      elsif promotion_code.respond_to?(:coupon)
        promotion_code.coupon
      end
    end

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
            turbo_stream.replace("next_bill", partial: "billing/next_bill"),
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
