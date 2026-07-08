require "test_helper"

class BillingSubscriptionsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot subscribe" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    post billing_subscription_path(plan: "starter")
    assert_redirected_to root_path
  end

  test "subscribing without a payment method on file is refused" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_resolvable_price(Billing::Plans::STARTER) do
      assert_no_difference "Pay::Subscription.count" do
        post billing_subscription_path(plan: "starter")
      end
    end

    assert_redirected_to billing_path
  end

  test "the owner can subscribe to a paid plan once a payment method exists" do
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    post login_path, params: { email: @owner.email, password: "password123" }

    with_resolvable_price(Billing::Plans::STARTER) do
      assert_difference "Pay::Subscription.count", 1 do
        post billing_subscription_path(plan: "starter")
      end
    end

    assert_redirected_to billing_path
    assert AuditLog.exists?(event_type: :subscription_created, resource_type: "Organization", resource_id: @organization.id)
  end

  test "subscribing sends default_payment_method (not payment_method) to Stripe" do
    # Pay's fake processor doesn't validate Stripe's actual parameter names, so this exercises
    # the real Pay::Stripe::Customer#subscribe call path (stubbing only the Stripe SDK boundary)
    # to pin down the exact request shape Stripe expects - regression test for a prior bug where
    # `payment_method:` was sent instead of `default_payment_method:` and Stripe rejected it with
    # "Received unknown parameter: payment_method".
    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")
    customer.payment_methods.create!(processor_id: "pm_test123", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    post login_path, params: { email: @owner.email, password: "password123" }

    captured_params = nil
    fake_stripe_subscription = Struct.new(:id).new("sub_test123")
    fake_pay_subscription = Object.new.tap { |o| o.define_singleton_method(:incomplete?) { false } }

    Stripe::Subscription.stub(:create, ->(params, _opts) { captured_params = params; fake_stripe_subscription }) do
      Pay::Stripe::Subscription.stub(:sync, fake_pay_subscription) do
        with_resolvable_price(Billing::Plans::STARTER) do
          post billing_subscription_path(plan: "starter")
        end
      end
    end

    assert_redirected_to billing_path
    assert_equal "pm_test123", captured_params[:default_payment_method]
    assert_not captured_params.key?(:payment_method)
  end

  test "the owner can switch from one paid plan to another without creating a second subscription" do
    post login_path, params: { email: @owner.email, password: "password123" }

    # A real already-subscribed org always has a payment method synced from Stripe by this
    # point - set one up so this matches realistic state for the swap guard clause.
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      with_resolvable_price(Billing::Plans::GROWTH) do
        assert_no_difference "Pay::Subscription.count" do
          post billing_subscription_path(plan: "growth")
        end
      end
    end

    assert_redirected_to billing_path
    assert AuditLog.exists?(event_type: :subscription_updated, resource_type: "Organization", resource_id: @organization.id)
  end

  test "checkout is refused for the Free plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    post billing_subscription_path(plan: "free")
    assert_redirected_to billing_path
  end

  test "checkout is refused for an unknown plan key" do
    post login_path, params: { email: @owner.email, password: "password123" }

    post billing_subscription_path(plan: "enterprise")
    assert_redirected_to billing_path
  end

  test "in non-production, canceling ends the subscription immediately" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      delete billing_subscription_path
    end

    assert_redirected_to billing_path
    assert_not @organization.payment_processor.subscription.reload.active?
    audit_log = AuditLog.where(event_type: :subscription_cancelled, resource_id: @organization.id).last
    assert audit_log.present?
    assert_equal true, audit_log.metadata["immediate"]
  end

  test "in production, canceling keeps access until the end of the billing period" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      Rails.env.stub(:production?, true) do
        delete billing_subscription_path
      end
    end

    assert_redirected_to billing_path
    subscription = @organization.payment_processor.subscription.reload
    assert subscription.active?
    assert subscription.ends_at.present?
  end

  test "canceling with no active subscription is a no-op redirect" do
    post login_path, params: { email: @owner.email, password: "password123" }

    delete billing_subscription_path
    assert_redirected_to billing_path
  end
end
