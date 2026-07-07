require "test_helper"

class BillingCheckoutsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot start a checkout" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    post billing_checkouts_path(plan: "starter")
    assert_redirected_to root_path
  end

  test "the owner is redirected to a Stripe-hosted checkout session for a paid plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    # Checkout Session creation is a real-Stripe-API concern that Pay's fake processor
    # doesn't model, so this stubs the Stripe SDK boundary directly (both the customer
    # auto-creation and the checkout session creation Pay::Stripe::Customer#checkout makes),
    # plus the plan's resolved price id (test credentials carry no real Stripe price ids),
    # rather than pulling in VCR/WebMock for one narrow assertion.
    fake_customer = Struct.new(:id).new("cus_test123")
    fake_session = Struct.new(:url).new("https://checkout.stripe.example/session/123")

    with_resolvable_starter_price("price_test_starter") do
      Stripe::Customer.stub(:create, fake_customer) do
        Stripe::Checkout::Session.stub(:create, fake_session) do
          post billing_checkouts_path(plan: "starter")
        end
      end
    end

    assert_redirected_to fake_session.url
  end

  test "checkout is refused for the Free plan" do
    post login_path, params: { email: @owner.email, password: "password123" }

    post billing_checkouts_path(plan: "free")
    assert_redirected_to billing_path
  end

  test "checkout is refused for an unknown plan key" do
    post login_path, params: { email: @owner.email, password: "password123" }

    post billing_checkouts_path(plan: "enterprise")
    assert_redirected_to billing_path
  end

  test "checkout is refused when the plan has no Stripe price id configured" do
    post login_path, params: { email: @owner.email, password: "password123" }

    post billing_checkouts_path(plan: "starter")
    assert_redirected_to billing_path
  end

  private

  # Test credentials carry no real Stripe price ids, so Billing::Plans::STARTER's
  # (frozen Data instance) resolved_stripe_price_id is normally blank. Stubs the class-level
  # lookup instead of the frozen constant itself.
  def with_resolvable_starter_price(price_id)
    resolvable = Billing::Plans::Plan.new(
      key: "starter", name: "Starter", price_cents: 1000, member_limit: 5, stripe_price_id: price_id
    )
    Billing::Plans.stub(:find, ->(key) { key.to_s == "starter" ? resolvable : Billing::Plans::ALL.find { |p| p.key == key.to_s } }) do
      yield
    end
  end
end
