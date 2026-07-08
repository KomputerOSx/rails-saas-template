module Billing
  class Plans
    SUPPORTED_CURRENCIES = %w[usd gbp].freeze
    DEFAULT_CURRENCY = "usd"

    Price = Data.define(:cents, :stripe_price_id) do
      def resolved_stripe_price_id
        stripe_price_id.respond_to?(:call) ? stripe_price_id.call : stripe_price_id
      end
    end

    # `prices` is a currency => Price hash - a Stripe Price (and therefore a subscription) is
    # always denominated in exactly one fixed currency, so switching currency on the billing
    # page means picking a different Price entirely, not converting an amount. See
    # docs/BILLING.md for the Stripe dashboard setup (one Price per plan per currency).
    Plan = Data.define(:key, :name, :member_limit, :prices) do
      def free? = key == "free"

      def price_for(currency)
        prices.fetch(currency.to_s) { prices.fetch(Plans::DEFAULT_CURRENCY) }
      end

      def price_cents(currency) = price_for(currency).cents

      def formatted_price(currency)
        Pay::Currency.format(price_cents(currency), currency: currency)
      end

      def resolved_stripe_price_id(currency) = price_for(currency).resolved_stripe_price_id
    end

    FREE = Plan.new(key: "free", name: "Free", member_limit: 1, prices: {
      "usd" => Price.new(cents: 0, stripe_price_id: nil),
      "gbp" => Price.new(cents: 0, stripe_price_id: nil)
    })
    STARTER = Plan.new(key: "starter", name: "Starter", member_limit: 5, prices: {
      "usd" => Price.new(cents: 999, stripe_price_id: -> { Rails.application.credentials.dig(:stripe, :price_ids, :starter, :usd) }),
      "gbp" => Price.new(cents: 999, stripe_price_id: -> { Rails.application.credentials.dig(:stripe, :price_ids, :starter, :gbp) })
    })
    GROWTH = Plan.new(key: "growth", name: "Growth", member_limit: 20, prices: {
      "usd" => Price.new(cents: 2999, stripe_price_id: -> { Rails.application.credentials.dig(:stripe, :price_ids, :growth, :usd) }),
      "gbp" => Price.new(cents: 2999, stripe_price_id: -> { Rails.application.credentials.dig(:stripe, :price_ids, :growth, :gbp) })
    })

    ALL = [ FREE, STARTER, GROWTH ].freeze
    PAID = [ STARTER, GROWTH ].freeze

    def self.find(key)
      ALL.find { |plan| plan.key == key.to_s }
    end

    # Stripe price ids are unique per account regardless of currency, so a subscription's
    # processor_plan alone is enough to find the right plan without already knowing which
    # currency it was purchased in.
    def self.for_stripe_price(stripe_price_id)
      return nil if stripe_price_id.blank?
      PAID.find { |plan| SUPPORTED_CURRENCIES.any? { |currency| plan.resolved_stripe_price_id(currency) == stripe_price_id } }
    end

    # Which of SUPPORTED_CURRENCIES a given Stripe price id was configured under, if any.
    def self.currency_for_stripe_price(stripe_price_id)
      return nil if stripe_price_id.blank?
      PAID.each do |plan|
        SUPPORTED_CURRENCIES.each do |currency|
          return currency if plan.resolved_stripe_price_id(currency) == stripe_price_id
        end
      end
      nil
    end
  end
end
