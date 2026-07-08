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

  test "a first Starter subscribe starts the 14-day free trial" do
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    post login_path, params: { email: @owner.email, password: "password123" }

    with_resolvable_price(Billing::Plans::STARTER) do
      assert_difference "Pay::Subscription.count", 1 do
        post billing_subscription_path(plan: "starter")
      end
    end

    assert_redirected_to billing_path
    assert @organization.reload.trial_used_at.present?
    assert @organization.payment_processor.subscription.trial_ends_at.present?
    audit_log = AuditLog.where(event_type: :subscription_created, resource_id: @organization.id).last
    assert_equal true, audit_log.metadata["trial"]
  end

  test "subscribing to Starter again after a used trial charges immediately with no trial" do
    @organization.update!(trial_used_at: 1.year.ago)
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    post login_path, params: { email: @owner.email, password: "password123" }

    with_resolvable_price(Billing::Plans::STARTER) do
      post billing_subscription_path(plan: "starter")
    end

    assert_redirected_to billing_path
    assert_nil @organization.payment_processor.subscription.trial_ends_at
  end

  test "subscribing to Growth from Free never gets a trial (Starter-only)" do
    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    post login_path, params: { email: @owner.email, password: "password123" }

    with_resolvable_price(Billing::Plans::GROWTH) do
      post billing_subscription_path(plan: "growth")
    end

    assert_redirected_to billing_path
    assert_nil @organization.reload.trial_used_at
    assert_nil @organization.payment_processor.subscription.trial_ends_at
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
    # Fresh org + Starter = trial path, which must ride the same subscribe call.
    assert_equal Organization::TRIAL_DAYS, captured_params[:trial_period_days]
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

  test "switching to a plan you're already on is refused" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      with_resolvable_price(Billing::Plans::STARTER) do
        assert_no_difference "AuditLog.count" do
          post billing_subscription_path(plan: "starter")
        end
      end

      assert_equal "price_fake_starter_usd", @organization.payment_processor.subscription.processor_plan
    end

    assert_redirected_to billing_path
  end

  test "downgrading schedules the change for period end instead of applying it now" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    phase_item = Struct.new(:price, :quantity).new("price_fake_growth_usd", 1)
    phase = Struct.new(:items, :start_date, :end_date).new([ phase_item ], 10.days.ago.to_i, 20.days.from_now.to_i)
    fake_schedule = Struct.new(:id, :phases).new("sub_sched_test123", [ phase ])

    with_active_subscription(@organization, Billing::Plans::GROWTH) do
      with_resolvable_price(Billing::Plans::STARTER) do
        Stripe::SubscriptionSchedule.stub(:create, fake_schedule) do
          Stripe::SubscriptionSchedule.stub(:update, fake_schedule) do
            post billing_subscription_path(plan: "starter")
          end
        end
      end

      # Still on Growth until Stripe flips the price at renewal.
      assert_equal "price_fake_growth_usd", @organization.payment_processor.subscription.processor_plan
    end

    assert_redirected_to billing_path
    assert_equal "starter", @organization.reload.pending_plan_key
    assert AuditLog.exists?(event_type: :subscription_downgrade_scheduled, resource_id: @organization.id)
  end

  test "the owner can cancel the scheduled downgrade to keep the current plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    @organization.update!(pending_plan_key: "starter", pending_plan_change_at: 20.days.from_now,
      stripe_subscription_schedule_id: "sub_sched_test123")

    Stripe::SubscriptionSchedule.stub(:release, true) do
      delete billing_subscription_scheduled_change_path
    end

    assert_redirected_to billing_path
    assert_nil @organization.reload.pending_plan_key
    assert AuditLog.exists?(event_type: :subscription_downgrade_cancelled, resource_id: @organization.id)
  end

  test "canceling a scheduled change when none exists shows an alert" do
    post login_path, params: { email: @owner.email, password: "password123" }

    delete billing_subscription_scheduled_change_path
    assert_redirected_to billing_path
    assert_nil AuditLog.find_by(event_type: :subscription_downgrade_cancelled, resource_id: @organization.id)
  end

  test "canceling keeps access until the end of the billing period in every environment" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      delete billing_subscription_path

      subscription = @organization.payment_processor.subscription.reload
      assert subscription.active?
      assert subscription.ends_at.present?
      assert subscription.on_grace_period?
    end

    assert_redirected_to billing_path
    assert AuditLog.exists?(event_type: :subscription_cancelled, resource_id: @organization.id)
  end

  test "canceling twice is refused while already in the grace period" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      delete billing_subscription_path
      assert_no_difference "AuditLog.where(event_type: :subscription_cancelled).count" do
        delete billing_subscription_path
      end
    end

    assert_redirected_to billing_path
  end

  test "the owner can resume a cancelled subscription during the grace period" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      @organization.payment_processor.subscription.cancel

      post billing_subscription_resume_path

      subscription = @organization.payment_processor.subscription.reload
      assert subscription.active?
      assert_nil subscription.ends_at
    end

    assert_redirected_to billing_path
    assert AuditLog.exists?(event_type: :subscription_resumed, resource_id: @organization.id)
  end

  test "resuming with nothing cancelled shows an alert" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      post billing_subscription_resume_path
    end

    assert_redirected_to billing_path
    assert_nil AuditLog.find_by(event_type: :subscription_resumed, resource_id: @organization.id)
  end

  test "a non-owner cannot resume or cancel scheduled changes" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    post billing_subscription_resume_path
    assert_redirected_to root_path

    delete billing_subscription_scheduled_change_path
    assert_redirected_to root_path
  end

  test "canceling with no active subscription is a no-op redirect" do
    post login_path, params: { email: @owner.email, password: "password123" }

    delete billing_subscription_path
    assert_redirected_to billing_path
  end
end
