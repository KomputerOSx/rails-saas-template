require "test_helper"

class BillingSetupIntentsTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot create a setup intent" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    post billing_setup_intent_path, as: :json
    assert_redirected_to root_path
  end

  test "the owner receives a client secret for the embedded card form" do
    post login_path, params: { email: @owner.email, password: "password123" }

    # No Stripe Customer exists yet for a brand-new org, so create_setup_intent also
    # triggers Pay's lazy customer auto-creation (Stripe::Customer.create) first.
    fake_customer = Struct.new(:id).new("cus_test123")
    fake_intent = Struct.new(:client_secret).new("seti_test_secret_123")

    Stripe::Customer.stub(:create, fake_customer) do
      Stripe::SetupIntent.stub(:create, fake_intent) do
        post billing_setup_intent_path, as: :json
      end
    end

    assert_response :success
    assert_equal({ "client_secret" => "seti_test_secret_123" }, JSON.parse(@response.body))
  end
end
