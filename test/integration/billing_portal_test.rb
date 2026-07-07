require "test_helper"

class BillingPortalTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot open the billing portal" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    post billing_portal_session_path
    assert_redirected_to root_path
  end

  test "the owner is redirected to billing without a Stripe account yet" do
    post login_path, params: { email: @owner.email, password: "password123" }

    post billing_portal_session_path
    assert_redirected_to billing_path
  end

  test "the owner is redirected to the Stripe billing portal once a Stripe customer exists" do
    post login_path, params: { email: @owner.email, password: "password123" }

    customer = @organization.set_payment_processor(:stripe)
    customer.update!(processor_id: "cus_test123")

    fake_portal = Struct.new(:url).new("https://billing.stripe.example/portal/abc")
    Stripe::BillingPortal::Session.stub(:create, fake_portal) do
      post billing_portal_session_path
    end

    assert_redirected_to fake_portal.url
  end
end
