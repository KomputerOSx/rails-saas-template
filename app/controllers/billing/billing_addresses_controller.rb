module Billing
  class BillingAddressesController < ApplicationController
    def update
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      Current.organization.sync_billing_details!(name: organization_params[:billing_name], address: address_params)
      log_audit(:billing_details_updated, resource: Current.organization)

      respond_with_success("Billing details updated.")
    rescue Pay::Stripe::Error => e
      respond_with_failure(e.message)
    end

    private

    def organization_params
      params.require(:organization).permit(:billing_name)
    end

    def address_params
      params.require(:organization).permit(
        :billing_address_line1, :billing_address_line2, :billing_address_city,
        :billing_address_state, :billing_address_postal_code, :billing_address_country
      ).to_h.transform_keys { |key| key.delete_prefix("billing_address_") }.symbolize_keys
    end

    def respond_with_success(message)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:toast] = { message: message, type: "success" }
          render turbo_stream: [
            turbo_stream.replace(dom_id(Current.organization, :billing_address_display),
              partial: "billing/billing_address_display", locals: { organization: Current.organization }),
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
