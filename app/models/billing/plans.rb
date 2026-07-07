module Billing
  class Plans
    Plan = Data.define(:key, :name, :price_cents, :member_limit, :stripe_price_id) do
      def free? = price_cents.zero?

      def price_dollars = price_cents / 100

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
