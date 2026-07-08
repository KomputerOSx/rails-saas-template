require "test_helper"

class BillingPromoCodesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = users(:one)
    @organization = Organization.create_personal_for!(@owner)
  end

  test "a non-owner cannot apply a promo code" do
    member = users(:two)
    @organization.memberships.create!(user: member).grant_role!(Role.find_or_create_by!(scope: :app, name: Role::APP_USER))

    post login_path, params: { email: member.email, password: "password123" }

    post billing_promo_code_path, params: { code: "SAVE20" }
    assert_redirected_to root_path
  end

  test "applying a valid, active promo code stores it for the next subscribe/upgrade" do
    post login_path, params: { email: @owner.email, password: "password123" }

    coupon = Struct.new(:valid, :percent_off, :amount_off).new(true, 20, nil)
    promotion_code = Struct.new(:id, :code, :coupon).new("promo_test123", "SAVE20", coupon)

    Stripe::PromotionCode.stub(:list, [ promotion_code ]) do
      post billing_promo_code_path, params: { code: "save20" }
    end

    assert_redirected_to billing_path
    assert_equal "promo_test123", session[:promo_code_id]
    assert_match "20% off", session[:promo_code_display]
  end

  test "applying an unknown or expired code shows an alert and stores nothing" do
    post login_path, params: { email: @owner.email, password: "password123" }

    Stripe::PromotionCode.stub(:list, []) do
      post billing_promo_code_path, params: { code: "NOPE" }
    end

    assert_redirected_to billing_path
    assert_nil session[:promo_code_id]
  end

  test "an inactive coupon is rejected even if the promotion code itself is active" do
    post login_path, params: { email: @owner.email, password: "password123" }

    coupon = Struct.new(:valid, :percent_off, :amount_off).new(false, 20, nil)
    promotion_code = Struct.new(:id, :code, :coupon).new("promo_test123", "SAVE20", coupon)

    Stripe::PromotionCode.stub(:list, [ promotion_code ]) do
      post billing_promo_code_path, params: { code: "SAVE20" }
    end

    assert_nil session[:promo_code_id]
  end

  test "removing an applied promo code clears it" do
    post login_path, params: { email: @owner.email, password: "password123" }

    coupon = Struct.new(:valid, :percent_off, :amount_off).new(true, 20, nil)
    promotion_code = Struct.new(:id, :code, :coupon).new("promo_test123", "SAVE20", coupon)

    Stripe::PromotionCode.stub(:list, [ promotion_code ]) do
      post billing_promo_code_path, params: { code: "SAVE20" }
    end

    delete billing_promo_code_path
    assert_redirected_to billing_path
    assert_nil session[:promo_code_id]
    assert_nil session[:promo_code_display]
  end
end
