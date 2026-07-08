require "test_helper"

class Billing::PlansTest < ActiveSupport::TestCase
  test "find looks plans up by key" do
    assert_equal Billing::Plans::FREE, Billing::Plans.find("free")
    assert_equal Billing::Plans::STARTER, Billing::Plans.find(:starter)
    assert_equal Billing::Plans::GROWTH, Billing::Plans.find("growth")
    assert_nil Billing::Plans.find("nonexistent")
  end

  test "ALL lists plans cheapest first, PAID excludes Free" do
    assert_equal [ Billing::Plans::FREE, Billing::Plans::STARTER, Billing::Plans::GROWTH ], Billing::Plans::ALL
    assert_equal [ Billing::Plans::STARTER, Billing::Plans::GROWTH ], Billing::Plans::PAID
  end

  test "member limits match the two-tier spec" do
    assert_equal 1, Billing::Plans::FREE.member_limit
    assert_equal 5, Billing::Plans::STARTER.member_limit
    assert_equal 20, Billing::Plans::GROWTH.member_limit
  end

  test "for_stripe_price returns nil for a blank or unmatched price id" do
    assert_nil Billing::Plans.for_stripe_price(nil)
    assert_nil Billing::Plans.for_stripe_price("")
    assert_nil Billing::Plans.for_stripe_price("price_unknown")
  end

  test "currency_for_stripe_price returns nil for a blank or unmatched price id" do
    assert_nil Billing::Plans.currency_for_stripe_price(nil)
    assert_nil Billing::Plans.currency_for_stripe_price("price_unknown")
  end

  test "resolved_stripe_price_id calls a lambda price id lazily, per currency" do
    plan = build_plan(usd_id: -> { "price_from_lambda_usd" }, gbp_id: -> { "price_from_lambda_gbp" })

    assert_equal "price_from_lambda_usd", plan.resolved_stripe_price_id("usd")
    assert_equal "price_from_lambda_gbp", plan.resolved_stripe_price_id("gbp")
  end

  test "resolved_stripe_price_id passes a plain string id through unchanged" do
    plan = build_plan(usd_id: "price_plain")

    assert_equal "price_plain", plan.resolved_stripe_price_id("usd")
  end

  test "price_for falls back to the default currency for an unrecognized currency" do
    plan = build_plan

    assert_equal plan.price_for(Billing::Plans::DEFAULT_CURRENCY), plan.price_for("eur")
  end

  test "free? and formatted_price" do
    assert Billing::Plans::FREE.free?
    assert_not Billing::Plans::STARTER.free?
    assert_equal "$9.99", Billing::Plans::STARTER.formatted_price("usd")
    assert_equal "£9.99", Billing::Plans::STARTER.formatted_price("gbp")
    assert_equal "$29.99", Billing::Plans::GROWTH.formatted_price("usd")
  end

  test "formatted_price shows cents correctly for non-round amounts" do
    plan = build_plan(cents: 999)

    assert_equal "$9.99", plan.formatted_price("usd")
  end

  private

  def build_plan(cents: 500, usd_id: "price_test_usd", gbp_id: "price_test_gbp")
    Billing::Plans::Plan.new(key: "test", name: "Test", member_limit: 3, prices: {
      "usd" => Billing::Plans::Price.new(cents: cents, stripe_price_id: usd_id),
      "gbp" => Billing::Plans::Price.new(cents: cents, stripe_price_id: gbp_id)
    })
  end
end
