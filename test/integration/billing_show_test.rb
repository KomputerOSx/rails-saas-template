require "test_helper"

class BillingShowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "billing history paginates at 10 charges per page" do
    customer = @organization.set_payment_processor(:stripe)
    15.times do |i|
      customer.charges.create!(processor_id: "ch_fake_#{i}", amount: 999, currency: "usd", created_at: i.days.ago)
    end

    post login_path, params: { email: @owner.email, password: "password123" }

    get billing_path
    assert_response :success
    assert_select "table tbody tr", 10
    assert_select "a", text: "Next"

    get billing_path, params: { charges_page: 2 }
    assert_response :success
    assert_select "table tbody tr", 5
    assert_select "a", text: "Previous"
  end

  test "billing history shows no pagination controls when everything fits on one page" do
    customer = @organization.set_payment_processor(:stripe)
    3.times { |i| customer.charges.create!(processor_id: "ch_fake_#{i}", amount: 999, currency: "usd") }

    post login_path, params: { email: @owner.email, password: "password123" }

    get billing_path
    assert_response :success
    assert_select "table tbody tr", 3
    assert_select "a", text: "Next", count: 0
  end

  test "cancel subscription button is not shown while on Free" do
    post login_path, params: { email: @owner.email, password: "password123" }

    get billing_path
    assert_response :success
    assert_select "button", text: "Cancel subscription", count: 0
  end

  test "cancel subscription button is shown while on a paid plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      get billing_path
    end

    assert_response :success
    assert_select "button", text: "Cancel subscription"
  end

  test "a cancelled subscription shows the resume banner and hides plan changes" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      @organization.payment_processor.subscription.cancel
      get billing_path
    end

    assert_response :success
    assert_select "button", text: "Resume subscription"
    assert_select "button", text: "Cancel subscription", count: 0
    assert_select "button", text: "Upgrade", count: 0
  end

  test "a scheduled downgrade shows the pending notice with an undo button" do
    post login_path, params: { email: @owner.email, password: "password123" }

    @organization.update!(pending_plan_key: "starter", pending_plan_change_at: 20.days.from_now,
      stripe_subscription_schedule_id: "sub_sched_test123")

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      get billing_path
    end

    assert_response :success
    assert_select "button", text: "Keep current plan"
    assert_match "Your plan changes to", response.body
  end

  test "a trialing subscription shows the trial notice" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      @organization.payment_processor.subscription.update!(trial_ends_at: 10.days.from_now)
      get billing_path
    end

    assert_response :success
    assert_match "Free trial", response.body
  end

  test "an eligible Free org sees the trial call-to-action on the Starter card" do
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    post login_path, params: { email: @owner.email, password: "password123" }

    get billing_path
    assert_response :success
    assert_match "Start #{Organization::TRIAL_DAYS}-day free trial", response.body

    @organization.update!(trial_used_at: Time.current)
    get billing_path
    assert_no_match "Start #{Organization::TRIAL_DAYS}-day free trial", response.body
  end

  test "a refunded charge is badged in billing history" do
    customer = @organization.set_payment_processor(:stripe)
    customer.charges.create!(processor_id: "ch_refunded", amount: 999, amount_refunded: 999, currency: "usd")
    customer.charges.create!(processor_id: "ch_partial", amount: 999, amount_refunded: 400, currency: "usd")

    post login_path, params: { email: @owner.email, password: "password123" }

    get billing_path
    assert_response :success
    assert_match "Partially refunded", response.body
    assert_match(/>\s*Refunded\s*</, response.body)
  end

  test "shows the live next-bill preview amount for an active subscription" do
    post login_path, params: { email: @owner.email, password: "password123" }

    fake_preview = Struct.new(:total, :currency).new(0, "usd")

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      Stripe::Invoice.stub(:create_preview, fake_preview) do
        get billing_path
      end
    end

    assert_response :success
    assert_match "Your next bill is", response.body
    assert_match "$0.00", response.body
  end

  test "falls back to the static plan price if the next-bill preview call fails" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      Stripe::Invoice.stub(:create_preview, ->(*) { raise Stripe::StripeError, "boom" }) do
        get billing_path
      end
    end

    assert_response :success
    assert_match Billing::Plans::STARTER.formatted_price("usd"), response.body
  end

  test "shows no next-bill line while on Free" do
    post login_path, params: { email: @owner.email, password: "password123" }

    get billing_path
    assert_response :success
    assert_no_match "Your next bill is", response.body
  end
end
