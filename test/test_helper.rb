ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Each parallel worker gets its own test database - load the reference-data seeds
    # (system_admin, owner/admin/user roles and their permissions) into each one, once,
    # outside any per-test transaction, so tests exercise the real seeded permission
    # catalog instead of ad-hoc reimplementations of it. Below the parallelization
    # threshold Rails runs single-process and parallelize_setup never fires, so seed
    # loading also happens unconditionally right here.
    parallelize_setup do |_worker|
      Rails.application.load_seed
    end
    Rails.application.load_seed

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rails.cache is a real (in-memory) store in test (see config/environments/test.rb)
    # so cache-backed state - PendingRegistration, Rack::Attack's throttle counters -
    # persists across requests within a test. Without this, repeated login/signup
    # attempts across different test cases in the same worker would accumulate and
    # trip rate limits that have nothing to do with the test being run.
    setup { Rails.cache.clear }

    # Gives an organization an active paid subscription for the duration of the block, using
    # Pay's fake processor (no network calls) plus stubs of Billing::Plans.for_stripe_price and
    # .currency_for_stripe_price so Organization#current_plan/#billing_currency resolve to
    # `plan`/`currency` without needing real Stripe price ids in test credentials. Wrap any
    # assertions that depend on the organization's plan/seat limit/currency in this block.
    def with_active_subscription(organization, plan, currency: Billing::Plans::DEFAULT_CURRENCY)
      customer = organization.set_payment_processor(:fake_processor, allow_fake: true)
      customer.subscribe(plan: "price_fake_#{plan.key}_#{currency}")

      Billing::Plans.stub(:for_stripe_price, plan) do
        Billing::Plans.stub(:currency_for_stripe_price, currency) { yield }
      end
    end

    # Makes Billing::Plans.find(plan.key) resolve to a plan with real (fake) Stripe price ids
    # for every supported currency, for the duration of the block, without touching real
    # Stripe credentials (test credentials carry none). Returns a separate Plan value (not
    # `plan` itself, which stays untouched for identity/equality comparisons elsewhere, e.g.
    # Organization#current_plan == Billing::Plans::STARTER) - only #resolved_stripe_price_id
    # from the stubbed lookup needs to be non-blank.
    def with_resolvable_price(plan)
      resolvable_prices = plan.prices.to_h { |currency, price|
        [ currency, Billing::Plans::Price.new(cents: price.cents, stripe_price_id: "price_fake_#{plan.key}_#{currency}") ]
      }
      resolvable_plan = Billing::Plans::Plan.new(
        key: plan.key,
        name: plan.name,
        member_limit: plan.member_limit,
        custom_domain: plan.custom_domain,
        prices: resolvable_prices
      )

      Billing::Plans.stub(:find, ->(key) { key.to_s == plan.key ? resolvable_plan : Billing::Plans::ALL.find { |p| p.key == key.to_s } }) do
        yield
      end
    end

    # Add more helper methods to be used by all tests here...
  end
end
