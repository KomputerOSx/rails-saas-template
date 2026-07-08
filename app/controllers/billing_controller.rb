class BillingController < ApplicationController
  CHARGES_PER_PAGE = 10

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

    charges = Current.organization.payment_processor&.charges&.order(created_at: :desc) || Pay::Charge.none
    @charges_page = [ params[:charges_page].to_i, 1 ].max
    @charges_total_pages = (charges.count / CHARGES_PER_PAGE.to_f).ceil
    @charges = charges.offset((@charges_page - 1) * CHARGES_PER_PAGE).limit(CHARGES_PER_PAGE)
  end
end
