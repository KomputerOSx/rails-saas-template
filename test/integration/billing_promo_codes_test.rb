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

  test "applying a code on a Stripe account using the newer polymorphic promotion.coupon shape" do
    # Regression test: Stripe moved PromotionCode#coupon to a polymorphic
    # PromotionCode#promotion.coupon as of the 2025-09-30 API version - #coupon doesn't exist
    # at all on that shape (not just nil), so this object deliberately has no #coupon method.
    post login_path, params: { email: @owner.email, password: "password123" }

    coupon = Struct.new(:valid, :percent_off, :amount_off).new(true, 20, nil)
    promotion = Struct.new(:type, :coupon).new("coupon", coupon)
    promotion_code = Struct.new(:id, :code, :promotion).new("promo_test123", "SAVE20", promotion)

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

  test "applying a code while already subscribed attaches it to the live subscription immediately" do
    post login_path, params: { email: @owner.email, password: "password123" }

    coupon = Struct.new(:valid, :percent_off, :amount_off).new(true, 20, nil)
    promotion_code = Struct.new(:id, :code, :coupon).new("promo_test123", "SAVE20", coupon)
    captured_args = nil

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      Stripe::Subscription.stub(:update, ->(id, params) { captured_args = [ id, params ] }) do
        Stripe::PromotionCode.stub(:list, [ promotion_code ]) do
          post billing_promo_code_path, params: { code: "SAVE20" }
        end
      end
    end

    assert_redirected_to billing_path
    assert_equal [ { promotion_code: "promo_test123" } ], captured_args[1][:discounts]
    assert_equal "promo_test123", session[:promo_code_id]
    assert_equal true, session[:promo_code_applied_live]
    assert AuditLog.exists?(event_type: :promotion_code_applied, resource_type: "Organization", resource_id: @organization.id)
  end

  test "removing a live-applied code strips it from the subscription, not just the session" do
    post login_path, params: { email: @owner.email, password: "password123" }

    coupon = Struct.new(:valid, :percent_off, :amount_off).new(true, 20, nil)
    promotion_code = Struct.new(:id, :code, :coupon).new("promo_test123", "SAVE20", coupon)
    captured_args = nil

    with_active_subscription(@organization, Billing::Plans::STARTER) do
      Stripe::Subscription.stub(:update, ->(id, params) { captured_args = [ id, params ] }) do
        Stripe::PromotionCode.stub(:list, [ promotion_code ]) do
          post billing_promo_code_path, params: { code: "SAVE20" }
        end

        delete billing_promo_code_path
      end
    end

    assert_redirected_to billing_path
    assert_equal [], captured_args[1][:discounts]
    assert_nil session[:promo_code_id]
    assert AuditLog.exists?(event_type: :promotion_code_removed, resource_type: "Organization", resource_id: @organization.id)
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
