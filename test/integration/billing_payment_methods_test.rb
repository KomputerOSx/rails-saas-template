require "test_helper"

class BillingPaymentMethodsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot update the payment method" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    post billing_payment_method_path, params: { setup_intent_id: "seti_test123" }
    assert_redirected_to root_path
  end

  test "a completed setup intent is synced and saved as the default payment method" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")
    # Already `default: true` so PaymentMethod#make_default! short-circuits before making
    # any Stripe API calls of its own - only Pay::Stripe::PaymentMethod.sync_setup_intent
    # needs stubbing below.
    payment_method = customer.payment_methods.create!(
      processor_id: "pm_test123", default: true, payment_method_type: "card", brand: "Visa", last4: "4242"
    )

    Pay::Stripe::PaymentMethod.stub(:sync_setup_intent, payment_method) do
      post billing_payment_method_path, params: { setup_intent_id: "seti_test123" }
    end

    assert_redirected_to billing_path
    assert AuditLog.exists?(event_type: :payment_method_updated, resource_type: "Organization", resource_id: @organization.id)
  end

  test "saving a card with a pending plan also subscribes to it in the same request" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")
    payment_method = customer.payment_methods.create!(
      processor_id: "pm_test123", default: true, payment_method_type: "card", brand: "Visa", last4: "4242"
    )

    fake_stripe_subscription = Struct.new(:id).new("sub_test123")
    fake_pay_subscription = Object.new.tap { |o| o.define_singleton_method(:incomplete?) { false } }

    Pay::Stripe::PaymentMethod.stub(:sync_setup_intent, payment_method) do
      Stripe::Subscription.stub(:create, fake_stripe_subscription) do
        Pay::Stripe::Subscription.stub(:sync, fake_pay_subscription) do
          with_resolvable_price(Billing::Plans::STARTER) do
            post billing_payment_method_path, params: { setup_intent_id: "seti_test123", plan: "starter" }
          end
        end
      end
    end

    assert_redirected_to billing_path
    assert AuditLog.exists?(event_type: :payment_method_updated, resource_type: "Organization", resource_id: @organization.id)
    assert AuditLog.exists?(event_type: :subscription_created, resource_type: "Organization", resource_id: @organization.id)
  end

  test "saving a card with no pending plan just saves the card (existing behavior)" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")
    payment_method = customer.payment_methods.create!(
      processor_id: "pm_test123", default: true, payment_method_type: "card", brand: "Visa", last4: "4242"
    )

    Pay::Stripe::PaymentMethod.stub(:sync_setup_intent, payment_method) do
      post billing_payment_method_path, params: { setup_intent_id: "seti_test123", plan: "" }
    end

    assert_redirected_to billing_path
    assert_not AuditLog.exists?(event_type: :subscription_created, resource_type: "Organization", resource_id: @organization.id)
  end

  test "an unresolvable setup intent shows an error instead of crashing" do
    post login_path, params: { email: @owner.email, password: "password123" }

    Pay::Stripe::PaymentMethod.stub(:sync_setup_intent, nil) do
      post billing_payment_method_path, params: { setup_intent_id: "seti_bad" }
    end

    assert_redirected_to billing_path
  end

  test "a non-owner cannot remove the payment method" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    delete billing_payment_method_path
    assert_redirected_to root_path
  end

  test "removing with no payment method on file shows an alert" do
    post login_path, params: { email: @owner.email, password: "password123" }

    delete billing_payment_method_path
    assert_redirected_to billing_path
  end

  test "the owner can remove their payment method while on the Free plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")
    customer.payment_methods.create!(processor_id: "pm_test123", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    Stripe::PaymentMethod.stub(:detach, true) do
      assert_difference "Pay::PaymentMethod.count", -1 do
        delete billing_payment_method_path
      end
    end

    assert_redirected_to billing_path
    assert_nil @organization.payment_processor.default_payment_method
    assert AuditLog.exists?(event_type: :payment_method_removed, resource_type: "Organization", resource_id: @organization.id)
  end

  test "removing the payment method is refused while subscribed to a paid plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.payment_methods.create!(processor_id: "pm_fake", default: true, payment_method_type: "card", brand: "Visa", last4: "4242")

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      assert_no_difference "Pay::PaymentMethod.count" do
        delete billing_payment_method_path
      end
    end

    assert_redirected_to billing_path
    assert @organization.payment_processor.default_payment_method.present?
  end
end
