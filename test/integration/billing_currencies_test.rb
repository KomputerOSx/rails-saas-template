require "test_helper"

class BillingCurrenciesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot switch currency" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    patch billing_currency_path, params: { currency: "gbp" }
    assert_redirected_to root_path
  end

  test "the owner can switch currency while on Free" do
    post login_path, params: { email: @owner.email, password: "password123" }

    patch billing_currency_path, params: { currency: "gbp" }

    assert_redirected_to billing_path
    assert_equal "gbp", @organization.reload.preferred_currency
  end

  test "an unsupported currency is rejected" do
    post login_path, params: { email: @owner.email, password: "password123" }

    patch billing_currency_path, params: { currency: "eur" }

    assert_redirected_to billing_path
    assert_equal "usd", @organization.reload.preferred_currency
  end

  test "switching currency is refused once subscribed to a paid plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      patch billing_currency_path, params: { currency: "gbp" }
    end

    assert_redirected_to billing_path
    assert_equal "usd", @organization.reload.preferred_currency
  end
end
