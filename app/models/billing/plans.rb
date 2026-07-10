module Billing
  class Plans
    SUPPORTED_CURRENCIES = %w[usd gbp].freeze
    DEFAULT_CURRENCY = "usd"

    Price = Data.define(:cents, :stripe_price_id) do
      def resolved_stripe_price_id
        stripe_price_id.respond_to?(:call) ? stripe_price_id.call : stripe_price_id
      end
    end

    Plan = Data.define(:key, :name, :member_limit, :custom_domain, :prices) do
      def free? = key == "free"

      def custom_domain? = custom_domain

      def price_for(currency)
        prices.fetch(currency.to_s) { prices.fetch(Plans::DEFAULT_CURRENCY) }
      end

      def price_cents(currency) = price_for(currency).cents

      def formatted_price(currency)
        Pay::Currency.format(price_cents(currency), currency: currency)
      end

      def resolved_stripe_price_id(currency) = price_for(currency).resolved_stripe_price_id

      def all_stripe_price_ids
        Plans::SUPPORTED_CURRENCIES.flat_map { |currency|
          [ resolved_stripe_price_id(currency), *Plans.legacy_price_ids(key, currency) ]
        }.compact
      end
    end

    FREE = Plan.new(key: "free", name: "Free", member_limit: 1, custom_domain: false, prices: {
      "usd" => Price.new(cents: 0, stripe_price_id: nil),
      "gbp" => Price.new(cents: 0, stripe_price_id: nil)
    })
    STARTER = Plan.new(key: "starter", name: "Starter", member_limit: 5, custom_domain: false, prices: {
      "usd" => Price.new(cents: 999, stripe_price_id: -> { credential_price_id(:starter, :usd) }),
      "gbp" => Price.new(cents: 999, stripe_price_id: -> { credential_price_id(:starter, :gbp) })
    })
    GROWTH = Plan.new(key: "growth", name: "Growth", member_limit: 20, custom_domain: true, prices: {
      "usd" => Price.new(cents: 4999, stripe_price_id: -> { credential_price_id(:growth, :usd) }),
      "gbp" => Price.new(cents: 2999, stripe_price_id: -> { credential_price_id(:growth, :gbp) })
    })

    ALL = [ FREE, STARTER, GROWTH ].freeze
    PAID = [ STARTER, GROWTH ].freeze

    def self.find(key)
      ALL.find { |plan| plan.key == key.to_s }
    end

    def self.credential_price_id(plan_key, currency)
      value = Rails.application.credentials.dig(:stripe, :price_ids, plan_key)
      value.is_a?(Hash) ? value[currency] : value
    end

    def self.legacy_price_ids(plan_key, currency)
      legacy = {
        "growth" => {
          "usd" => [ "price_1TqhWqRwyC7yy0N3ZtkgQg5U" ]
        }
      }
      legacy.dig(plan_key.to_s, currency.to_s) || []
    end

    def self.for_stripe_price(stripe_price_id)
      return nil if stripe_price_id.blank?
      PAID.find { |plan| plan.all_stripe_price_ids.include?(stripe_price_id) }
    end

    def self.currency_for_stripe_price(stripe_price_id)
      return nil if stripe_price_id.blank?
      PAID.each do |plan|
        SUPPORTED_CURRENCIES.each do |currency|
          if plan.resolved_stripe_price_id(currency) == stripe_price_id ||
             Plans.legacy_price_ids(plan.key, currency).include?(stripe_price_id)
            return currency
          end
        end
      end
      nil
    end
  end
end
