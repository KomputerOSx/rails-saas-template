module Billing
  class Plans
    # Must match whatever currency your Stripe Prices are actually denominated in - a Stripe
    # Price is tied to one fixed currency, so this can't vary per-request/per-customer without
    # setting up Stripe's multi-currency Prices feature (out of scope for this template's two
    # fixed tiers). Change this (e.g. to "gbp") if your account's prices aren't USD - it drives
    # both the displayed price below and must match what you actually charge, or the UI will
    # show the wrong currency symbol/amount for what Stripe actually bills.
    CURRENCY = "usd"

    Plan = Data.define(:key, :name, :price_cents, :member_limit, :stripe_price_id) do
      def free? = price_cents.zero?

      def formatted_price
        Pay::Currency.format(price_cents, currency: Plans::CURRENCY)
      end

      def resolved_stripe_price_id
        stripe_price_id.respond_to?(:call) ? stripe_price_id.call : stripe_price_id
      end
    end

    FREE = Plan.new(key: "free", name: "Free", price_cents: 0, member_limit: 1, stripe_price_id: nil)
    STARTER = Plan.new(key: "starter", name: "Starter", price_cents: 1000, member_limit: 5,
      stripe_price_id: -> { Rails.application.credentials.dig(:stripe, :price_ids, :starter) })
    GROWTH = Plan.new(key: "growth", name: "Growth", price_cents: 3000, member_limit: 20,
      stripe_price_id: -> { Rails.application.credentials.dig(:stripe, :price_ids, :growth) })

    ALL = [ FREE, STARTER, GROWTH ].freeze
    PAID = [ STARTER, GROWTH ].freeze

    def self.find(key)
      ALL.find { |plan| plan.key == key.to_s }
    end

    def self.for_stripe_price(stripe_price_id)
      return nil if stripe_price_id.blank?
      PAID.find { |plan| plan.resolved_stripe_price_id == stripe_price_id }
    end
  end
end
