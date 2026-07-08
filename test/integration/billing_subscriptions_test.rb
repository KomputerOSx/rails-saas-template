require "test_helper"

class BillingSubscriptionsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot cancel the subscription" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      delete billing_subscription_path
    end
    assert_redirected_to root_path
  end

  test "canceling with no active subscription redirects with an alert" do
    post login_path, params: { email: @owner.email, password: "password123" }

    delete billing_subscription_path
    assert_redirected_to billing_path
    follow_redirect!
    assert_match "no active subscription", flash[:alert]
  end

  test "the owner can cancel an active subscription and it stays available for the grace period" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      delete billing_subscription_path
    end

    assert_redirected_to billing_path
    subscription = @organization.payment_processor.subscription
    assert subscription.on_grace_period?
  end

  test "resuming with no cancellation in progress redirects with an alert" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      post resume_billing_subscription_path
    end

    assert_redirected_to billing_path
    follow_redirect!
    assert_match "no cancellation", flash[:alert]
  end

  test "the owner can resume a subscription that's on its grace period" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      delete billing_subscription_path
      post resume_billing_subscription_path
    end

    subscription = @organization.payment_processor.subscription
    assert_not subscription.on_grace_period?
    assert subscription.active?
  end
end
