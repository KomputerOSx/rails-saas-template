class BillingController < ApplicationController
  before_action { redirect_to dashboard_path, alert: "No organization selected." unless Current.organization }
  before_action { authorize Current.organization, :show?, policy_class: BillingPolicy }
  after_action :verify_authorized

  def show
    @plans = Billing::Plans::ALL
    @current_plan = Current.organization.current_plan
    @currency = Current.organization.billing_currency
    @member_usage = Current.organization.member_count_with_pending
    @member_limit = Current.organization.member_limit
    @payment_method = Current.organization.payment_processor&.default_payment_method
    @charges = Current.organization.payment_processor&.charges&.order(created_at: :desc)&.limit(10) || []
  end
end
