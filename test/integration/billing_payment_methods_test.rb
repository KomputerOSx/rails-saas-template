require "test_helper"

class BillingPaymentMethodsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot remove the payment method" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    delete billing_payment_method_path
    assert_redirected_to root_path
  end

  test "removing with no payment method on file redirects with an alert" do
    post login_path, params: { email: @owner.email, password: "password123" }

    delete billing_payment_method_path
    assert_redirected_to billing_path
    follow_redirect!
    assert_match "No payment method", flash[:alert]
  end

  test "the owner can remove the payment method on file" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    customer.add_payment_method("pm_fake_123", default: true)

    assert_difference "Pay::PaymentMethod.count", -1 do
      delete billing_payment_method_path
    end

    assert_redirected_to billing_path
    assert_nil Pay::PaymentMethod.find_by(customer: customer, default: true)
  end
end
