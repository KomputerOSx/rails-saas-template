require "test_helper"

class BillingShowTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "billing history shows the first 10 charges with a show more link for the rest" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:fake_processor, allow_fake: true)
    15.times { |i| customer.charge(1000, processor_id: "ch_#{i}") }

    get billing_path
    assert_response :success
    assert_select "table tbody tr", 10
    assert_select "a", text: "Show more"

    get billing_path(charges_limit: 20)
    assert_response :success
    assert_select "table tbody tr", 15
    assert_select "a", text: "Show more", count: 0
  end

  test "cancel subscription button only appears with an active paid plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    get billing_path
    assert_response :success
    assert_select "button", text: "Cancel subscription", count: 0

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      get billing_path
    end
    assert_response :success
    assert_select "button", text: "Cancel subscription", count: 1
  end
end
