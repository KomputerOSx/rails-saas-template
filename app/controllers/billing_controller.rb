class BillingController < ApplicationController
  before_action { redirect_to dashboard_path, alert: "No organization selected." unless Current.organization }
  before_action { authorize Current.organization, :show?, policy_class: BillingPolicy }
  after_action :verify_authorized

  def show
    @plans = Billing::Plans::ALL
    @current_plan = Current.organization.current_plan
    @member_usage = Current.organization.member_count_with_pending
    @member_limit = Current.organization.member_limit
    @has_billing_account = Current.organization.payment_processor&.processor_id.present?
    @payment_method = Current.organization.payment_processor&.default_payment_method
    @subscription = Current.organization.payment_processor&.subscription

    @charges_limit = charges_limit_param
    charges = Current.organization.payment_processor&.charges&.order(created_at: :desc)&.limit(@charges_limit + 1)&.to_a || []
    @more_charges = charges.size > @charges_limit
    @charges = charges.first(@charges_limit)
  end

  private

  def charges_limit_param
    limit = params[:charges_limit].to_i
    limit.positive? ? limit : 10
  end
end
