module Billing
  class CurrenciesController < ApplicationController
    def update
      authorize Current.organization, :manage?, policy_class: BillingPolicy

      organization = Current.organization
      unless organization.current_plan.free?
        return redirect_to billing_path, alert: "Currency is locked to your subscription once you're on a paid plan - cancel first to switch."
      end

      currency = params[:currency].to_s
      unless Billing::Plans::SUPPORTED_CURRENCIES.include?(currency)
        return redirect_to billing_path, alert: "Unsupported currency."
      end

      organization.update!(preferred_currency: currency)
      redirect_to billing_path, notice: "Prices now shown in #{currency.upcase}."
    end
  end
end
