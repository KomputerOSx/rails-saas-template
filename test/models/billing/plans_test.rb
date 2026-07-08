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

  test "resolved_stripe_price_id calls a lambda price id lazily" do
    plan = Billing::Plans::Plan.new(key: "test", name: "Test", price_cents: 500, member_limit: 3,
      stripe_price_id: -> { "price_from_lambda" })

    assert_equal "price_from_lambda", plan.resolved_stripe_price_id
  end

  test "resolved_stripe_price_id passes a plain string id through unchanged" do
    plan = Billing::Plans::Plan.new(key: "test", name: "Test", price_cents: 500, member_limit: 3,
      stripe_price_id: "price_plain")

    assert_equal "price_plain", plan.resolved_stripe_price_id
  end

  test "free? and formatted_price" do
    assert Billing::Plans::FREE.free?
    assert_not Billing::Plans::STARTER.free?
    assert_equal "$10.00", Billing::Plans::STARTER.formatted_price
    assert_equal "$30.00", Billing::Plans::GROWTH.formatted_price
  end

  test "formatted_price shows cents correctly for non-round amounts" do
    plan = Billing::Plans::Plan.new(key: "test", name: "Test", price_cents: 999, member_limit: 3, stripe_price_id: "price_test")

    assert_equal "$9.99", plan.formatted_price
  end
end
